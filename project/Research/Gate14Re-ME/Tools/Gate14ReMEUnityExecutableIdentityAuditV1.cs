#if UNITY_EDITOR
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using UnityEditor;
using UnityEngine;

namespace DDM.Research.Editor.UnityExecutableIdentityAuditAttempt001
{
    [Serializable]
    public sealed class IdentityAuditAuthorizationHeaderV1
    {
        public string schema;
        public string studyId;
        public string authorizationId;
        public string status;
    }

    [Serializable]
    public sealed class IdentityAuditFreezeManifestHeaderV1
    {
        public string schema;
        public string studyId;
        public string authorizationId;
        public string status;
    }

    [Serializable]
    public sealed class IdentityAuditFileBindingV1
    {
        public string role;
        public string relativePath;
        public long lengthBytes;
        public string expectedSha256;
        public string actualSha256;
        public bool matched;
    }

    [Serializable]
    public sealed class IdentityAuditHashMethodV1
    {
        public string method;
        public bool succeeded;
        public string sha256;
        public string exactFailure;
    }

    [Serializable]
    public sealed class IdentityAuditChunkHashV1
    {
        public int chunkIndex;
        public long offsetBytes;
        public int lengthBytes;
        public string sha256;
    }

    [Serializable]
    public sealed class IdentityAuditFileIdV1
    {
        public bool succeeded;
        public string normalizedPath;
        public string finalPath;
        public string volumeSerialHex;
        public string fileIndexHex;
        public string exactFailure;
    }

    [Serializable]
    public sealed class IdentityAuditPeIdentityV1
    {
        public bool succeeded;
        public long peHeaderOffset;
        public string optionalHeaderMagicHex;
        public long checksumFieldOffset;
        public string checksumHex;
        public long securityDirectoryFieldOffset;
        public long certificateTableFileOffset;
        public long certificateTableSizeBytes;
        public string exactFailure;
    }

    [Serializable]
    public sealed class IdentityAuditFileFingerprintV1
    {
        public string capturedAtUtc;
        public string path;
        public long lengthBytes;
        public string creationTimeUtc;
        public string lastWriteTimeUtc;
        public string attributes;
        public IdentityAuditFileIdV1 fileIdentity;
        public IdentityAuditPeIdentityV1 peIdentity;
        public IdentityAuditHashMethodV1[] fullFileHashes;
        public int chunkSizeBytes;
        public IdentityAuditChunkHashV1[] chunkHashes;
    }

    [Serializable]
    public sealed class IdentityAuditKnownAnswersV1
    {
        public string abcExpectedSha256;
        public string abcActualSha256;
        public bool abcPassed;
        public long zeroStreamLengthBytes;
        public string zeroStreamExpectedSha256;
        public string zeroStreamActualSha256;
        public bool zeroStreamPassed;
        public bool allPassed;
    }

    [Serializable]
    public sealed class IdentityAuditProcessObservationV1
    {
        public int processId;
        public string processStartTimeUtc;
        public string editorApplicationPath;
        public string processMainModulePath;
        public string queryFullProcessImageNamePath;
        public string[] environmentCommandLineArgs;
        public bool allExecutablePathsEqual;
        public string mainModuleExactFailure;
        public string queryFullProcessImageNameExactFailure;
    }

    [Serializable]
    public sealed class UnityIdentityReadySnapshotV1
    {
        public string schema;
        public string studyId;
        public string authorizationId;
        public string status;
        public string createdAtUtc;
        public IdentityAuditProcessObservationV1 process;
        public IdentityAuditKnownAnswersV1 sha256KnownAnswers;
        public IdentityAuditFileFingerprintV1 initialExecutableFingerprint;
        public int holdSeconds;
        public bool schemaCompatibilitySelfCheckInvoked;
        public bool algorithmCodeLoadedByAuditProject;
    }

    [Serializable]
    public sealed class UnityIdentityProbeReceiptV1
    {
        public string schema;
        public string studyId;
        public string authorizationId;
        public string status;
        public string startedAtUtc;
        public string completedAtUtc;
        public bool passed;
        public bool terminal;
        public IdentityAuditFileBindingV1[] bindings;
        public bool authorizationHeaderPassed;
        public bool freezeManifestHeaderPassed;
        public IdentityAuditProcessObservationV1 process;
        public IdentityAuditKnownAnswersV1 sha256KnownAnswers;
        public IdentityAuditFileFingerprintV1 initialExecutableFingerprint;
        public IdentityAuditFileFingerprintV1 afterHoldExecutableFingerprint;
        public bool inProcessFingerprintStableAcrossHold;
        public string priorAttemptInProcessSha256;
        public bool priorMismatchHashReproducedInitially;
        public bool priorMismatchHashReproducedAfterHold;
        public int holdSeconds;
        public bool schemaCompatibilitySelfCheckInvoked;
        public bool plannerInvoked;
        public bool algorithmLaneExecuted;
        public bool measuredRootCreated;
        public string exceptionType;
        public string exactFailure;
        public string stackTrace;
    }

    public static class Gate14ReMEUnityExecutableIdentityAuditV1
    {
        private const string StudyId = "Gate14Re-ME";
        private const string AuthorizationId = "gate14re-me-unity-executable-identity-discrepancy-audit-attempt-001";
        private const string ExpectedOutputRelativePath = "Research/Verification/Gate14Re-ME/unity-executable-identity-discrepancy-audit-attempt-001/unity-output";
        private const string ExpectedUnityPath = "H:/UnityEditor/2022.3.30f1c1/Editor/Unity.exe";
        private const string ExpectedExternalUnitySha256 = "0a69d14cbe2ca82d0a6168da8156d9e0dd138a6b7d0260dcdea31fd3957ca9cf";
        private const string PriorAttemptInProcessSha256 = "ad243c5b18041d674874864cea86626623ff366a6363aede529fec923e80579e";
        private const int ChunkSizeBytes = 65536;
        private const uint GenericReadAttributes = 0x00000080;
        private const uint ShareRead = 0x00000001;
        private const uint ShareWrite = 0x00000002;
        private const uint ShareDelete = 0x00000004;
        private const uint OpenExisting = 3;

        [StructLayout(LayoutKind.Sequential)]
        private struct NativeFileTime
        {
            public uint LowDateTime;
            public uint HighDateTime;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct ByHandleFileInformation
        {
            public uint FileAttributes;
            public NativeFileTime CreationTime;
            public NativeFileTime LastAccessTime;
            public NativeFileTime LastWriteTime;
            public uint VolumeSerialNumber;
            public uint FileSizeHigh;
            public uint FileSizeLow;
            public uint NumberOfLinks;
            public uint FileIndexHigh;
            public uint FileIndexLow;
        }

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr CreateFileW(
            string fileName,
            uint desiredAccess,
            uint shareMode,
            IntPtr securityAttributes,
            uint creationDisposition,
            uint flagsAndAttributes,
            IntPtr templateFile);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetFileInformationByHandle(IntPtr file, out ByHandleFileInformation information);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern uint GetFinalPathNameByHandleW(IntPtr file, StringBuilder path, uint pathLength, uint flags);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool QueryFullProcessImageNameW(IntPtr process, uint flags, StringBuilder executablePath, ref uint size);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CloseHandle(IntPtr handle);

        public static void Run()
        {
            int exitCode = 1;
            string outputDirectory = null;
            UnityIdentityProbeReceiptV1 receipt = new UnityIdentityProbeReceiptV1
            {
                schema = "gate14re-me-unity-executable-identity-probe-receipt-v1",
                studyId = StudyId,
                authorizationId = AuthorizationId,
                status = "FAILED_CLOSED_ALGORITHM_FREE_UNITY_IDENTITY_PROBE",
                startedAtUtc = DateTime.UtcNow.ToString("o", CultureInfo.InvariantCulture),
                passed = false,
                terminal = false,
                priorAttemptInProcessSha256 = PriorAttemptInProcessSha256,
                schemaCompatibilitySelfCheckInvoked = false,
                plannerInvoked = false,
                algorithmLaneExecuted = false,
                measuredRootCreated = false
            };

            try
            {
                Dictionary<string, string> arguments = ParseArguments(Environment.GetCommandLineArgs());
                string sourceProjectRoot = Path.GetFullPath(Required(arguments, "--g14me-source-project-root"));
                outputDirectory = ResolveExactNewOutputDirectory(
                    sourceProjectRoot,
                    Required(arguments, "--g14me-identity-output-dir"));
                int holdSeconds = int.Parse(Required(arguments, "--g14me-hold-seconds"), CultureInfo.InvariantCulture);
                Require(holdSeconds == 30, "The authorized in-process observation hold must equal 30 seconds.");
                receipt.holdSeconds = holdSeconds;

                string authorizedUnityPath = NormalizePath(Required(arguments, "--g14me-authorized-unity-path"));
                string authorizedUnityHash = Required(arguments, "--g14me-authorized-unity-sha256").ToLowerInvariant();
                Require(PathsEqual(authorizedUnityPath, ExpectedUnityPath), "Authorized Unity path mismatch.");
                Require(authorizedUnityHash == ExpectedExternalUnitySha256, "Authorized external Unity SHA-256 mismatch.");

                List<IdentityAuditFileBindingV1> bindings = new List<IdentityAuditFileBindingV1>();
                BindAbsolute(bindings, "authorization", Required(arguments, "--g14me-authorization"), Required(arguments, "--g14me-authorization-sha256"));
                BindAbsolute(bindings, "plan", Required(arguments, "--g14me-plan"), Required(arguments, "--g14me-plan-sha256"));
                BindAbsolute(bindings, "source-freeze-manifest", Required(arguments, "--g14me-freeze-manifest"), Required(arguments, "--g14me-freeze-manifest-sha256"));
                BindRelative(sourceProjectRoot, bindings, "parent-status-v12",
                    "Research/Gate14Re-ME/Gate14Re_ME_Status.v12.json",
                    "a741f745ee58a8ec0ca505464078b1441161226e6cf278c57b9af76f2945846d");
                BindRelative(sourceProjectRoot, bindings, "retained-corrigendum-failure",
                    "Research/Verification/Gate14Re-ME/qualification-input-schema-compatibility-corrigendum-attempt-001/failure-receipt.v1.json",
                    "a92d258027ea0add02e874d3b73b20c7790f18b904af7d051a3ccc09e5eb69f1");
                BindRelative(sourceProjectRoot, bindings, "retained-corrigendum-post-exit-audit",
                    "Research/Verification/Gate14Re-ME/qualification-input-schema-compatibility-corrigendum-attempt-001/post-exit-unity-identity-audit.v1.json",
                    "9585fdc3b2b250dc1801d9a81d41d045cee1028a0d1d9707f982664133fcee41");
                BindRelative(sourceProjectRoot, bindings, "retained-corrigendum-freeze-manifest",
                    "Research/Verification/Gate14Re-ME/qualification-input-schema-compatibility-corrigendum-attempt-001/source-and-evidence-freeze-manifest.v1.json",
                    "9ad8a0ce59a286f5c32704f612154d6f751bb38d8bcd3003a8902da5bc1dc2b9");
                receipt.bindings = bindings.ToArray();

                IdentityAuditAuthorizationHeaderV1 authorization = JsonUtility.FromJson<IdentityAuditAuthorizationHeaderV1>(
                    File.ReadAllText(Required(arguments, "--g14me-authorization"), new UTF8Encoding(false, true)));
                receipt.authorizationHeaderPassed = authorization != null &&
                    authorization.schema == "gate14re-me-unity-executable-identity-discrepancy-audit-authorization-v1" &&
                    authorization.studyId == StudyId && authorization.authorizationId == AuthorizationId &&
                    authorization.status == "AUTHORIZED_ALGORITHM_FREE_UNITY_EXECUTABLE_IDENTITY_DISCREPANCY_AUDIT";
                Require(receipt.authorizationHeaderPassed, "Identity-audit authorization header mismatch.");

                IdentityAuditFreezeManifestHeaderV1 manifest = JsonUtility.FromJson<IdentityAuditFreezeManifestHeaderV1>(
                    File.ReadAllText(Required(arguments, "--g14me-freeze-manifest"), new UTF8Encoding(false, true)));
                receipt.freezeManifestHeaderPassed = manifest != null &&
                    manifest.schema == "gate14re-me-unity-executable-identity-audit-source-freeze-manifest-v1" &&
                    manifest.studyId == StudyId && manifest.authorizationId == AuthorizationId &&
                    manifest.status == "FROZEN_PREEXECUTION_IDENTITY_AUDIT_SOURCES";
                Require(receipt.freezeManifestHeaderPassed, "Identity-audit source freeze manifest header mismatch.");

                receipt.process = CaptureProcessObservation();
                Require(receipt.process.allExecutablePathsEqual, "Unity process executable paths do not agree.");
                Require(PathsEqual(receipt.process.editorApplicationPath, authorizedUnityPath), "Running Unity path differs from the authorized path.");

                FileInfo executableInfo = new FileInfo(receipt.process.editorApplicationPath);
                Require(executableInfo.Exists, "Running Unity executable is not readable as a file.");
                receipt.sha256KnownAnswers = RunKnownAnswers(
                    executableInfo.Length,
                    Required(arguments, "--g14me-zero-stream-sha256"));
                Require(receipt.sha256KnownAnswers.allPassed, "One or more SHA-256 known answers failed.");

                receipt.initialExecutableFingerprint = CaptureFileFingerprint(receipt.process.editorApplicationPath);
                string initialHash = RequiredHash(receipt.initialExecutableFingerprint, "sha256-create-file-open-read");
                receipt.priorMismatchHashReproducedInitially = initialHash == PriorAttemptInProcessSha256;

                UnityIdentityReadySnapshotV1 ready = new UnityIdentityReadySnapshotV1
                {
                    schema = "gate14re-me-unity-executable-identity-ready-snapshot-v1",
                    studyId = StudyId,
                    authorizationId = AuthorizationId,
                    status = "IN_PROCESS_IDENTITY_SNAPSHOT_READY",
                    createdAtUtc = DateTime.UtcNow.ToString("o", CultureInfo.InvariantCulture),
                    process = receipt.process,
                    sha256KnownAnswers = receipt.sha256KnownAnswers,
                    initialExecutableFingerprint = receipt.initialExecutableFingerprint,
                    holdSeconds = holdSeconds,
                    schemaCompatibilitySelfCheckInvoked = false,
                    algorithmCodeLoadedByAuditProject = false
                };
                WriteJsonAtomic(Path.Combine(outputDirectory, "in-process-ready-snapshot.v1.json"), ready);

                Thread.Sleep(checked(holdSeconds * 1000));

                receipt.afterHoldExecutableFingerprint = CaptureFileFingerprint(receipt.process.editorApplicationPath);
                string afterHash = RequiredHash(receipt.afterHoldExecutableFingerprint, "sha256-create-file-open-read");
                receipt.priorMismatchHashReproducedAfterHold = afterHash == PriorAttemptInProcessSha256;
                receipt.inProcessFingerprintStableAcrossHold = FingerprintsEqual(
                    receipt.initialExecutableFingerprint,
                    receipt.afterHoldExecutableFingerprint);
                Require(receipt.inProcessFingerprintStableAcrossHold, "The in-process executable fingerprint changed during the observation hold.");

                receipt.passed = true;
                receipt.terminal = true;
                receipt.status = "PASS_ALGORITHM_FREE_UNITY_IDENTITY_PROBE_EXTERNAL_ADJUDICATION_PENDING";
                exitCode = 0;
            }
            catch (Exception exception)
            {
                receipt.passed = false;
                receipt.terminal = true;
                receipt.status = "FAILED_CLOSED_ALGORITHM_FREE_UNITY_IDENTITY_PROBE";
                receipt.exceptionType = exception.GetType().FullName;
                receipt.exactFailure = exception.Message;
                receipt.stackTrace = exception.ToString();
                UnityEngine.Debug.LogException(exception);
            }
            finally
            {
                receipt.completedAtUtc = DateTime.UtcNow.ToString("o", CultureInfo.InvariantCulture);
                if (!string.IsNullOrEmpty(outputDirectory))
                {
                    try
                    {
                        WriteJsonAtomic(Path.Combine(outputDirectory, "unity-identity-probe-receipt.v1.json"), receipt);
                    }
                    catch (Exception writeException)
                    {
                        UnityEngine.Debug.LogException(writeException);
                        exitCode = 1;
                    }
                }
                EditorApplication.Exit(exitCode);
            }
        }

        private static IdentityAuditProcessObservationV1 CaptureProcessObservation()
        {
            Process current = Process.GetCurrentProcess();
            IdentityAuditProcessObservationV1 observation = new IdentityAuditProcessObservationV1
            {
                processId = current.Id,
                processStartTimeUtc = current.StartTime.ToUniversalTime().ToString("o", CultureInfo.InvariantCulture),
                editorApplicationPath = NormalizePath(EditorApplication.applicationPath),
                environmentCommandLineArgs = Environment.GetCommandLineArgs()
            };
            try
            {
                observation.processMainModulePath = NormalizePath(current.MainModule.FileName);
            }
            catch (Exception exception)
            {
                observation.mainModuleExactFailure = exception.GetType().FullName + ": " + exception.Message;
            }
            try
            {
                uint size = 32768;
                StringBuilder buffer = new StringBuilder((int)size);
                if (!QueryFullProcessImageNameW(current.Handle, 0, buffer, ref size))
                {
                    throw new InvalidOperationException("QueryFullProcessImageNameW failed with Win32 error " + Marshal.GetLastWin32Error().ToString(CultureInfo.InvariantCulture));
                }
                observation.queryFullProcessImageNamePath = NormalizePath(buffer.ToString());
            }
            catch (Exception exception)
            {
                observation.queryFullProcessImageNameExactFailure = exception.GetType().FullName + ": " + exception.Message;
            }
            observation.allExecutablePathsEqual =
                !string.IsNullOrEmpty(observation.processMainModulePath) &&
                !string.IsNullOrEmpty(observation.queryFullProcessImageNamePath) &&
                PathsEqual(observation.editorApplicationPath, observation.processMainModulePath) &&
                PathsEqual(observation.editorApplicationPath, observation.queryFullProcessImageNamePath);
            return observation;
        }

        private static IdentityAuditKnownAnswersV1 RunKnownAnswers(long zeroStreamLength, string expectedZeroStreamHash)
        {
            const string abcExpected = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad";
            string abcActual;
            using (SHA256 sha = SHA256.Create())
            {
                abcActual = Hex(sha.ComputeHash(Encoding.ASCII.GetBytes("abc")));
            }
            string zeroActual;
            using (SHA256 sha = SHA256.Create())
            using (ZeroStream stream = new ZeroStream(zeroStreamLength))
            {
                zeroActual = Hex(sha.ComputeHash(stream));
            }
            IdentityAuditKnownAnswersV1 result = new IdentityAuditKnownAnswersV1
            {
                abcExpectedSha256 = abcExpected,
                abcActualSha256 = abcActual,
                abcPassed = abcActual == abcExpected,
                zeroStreamLengthBytes = zeroStreamLength,
                zeroStreamExpectedSha256 = expectedZeroStreamHash.ToLowerInvariant(),
                zeroStreamActualSha256 = zeroActual,
                zeroStreamPassed = zeroActual == expectedZeroStreamHash.ToLowerInvariant()
            };
            result.allPassed = result.abcPassed && result.zeroStreamPassed;
            return result;
        }

        private static IdentityAuditFileFingerprintV1 CaptureFileFingerprint(string path)
        {
            string fullPath = Path.GetFullPath(path);
            FileInfo info = new FileInfo(fullPath);
            Require(info.Exists, "Executable file disappeared: " + fullPath);
            List<IdentityAuditHashMethodV1> methods = new List<IdentityAuditHashMethodV1>();
            methods.Add(CaptureHash("sha256-create-file-open-read", delegate
            {
                using (SHA256 sha = SHA256.Create())
                using (FileStream stream = File.OpenRead(fullPath))
                {
                    return Hex(sha.ComputeHash(stream));
                }
            }));
            methods.Add(CaptureHash("sha256-create-shared-filestream", delegate
            {
                using (SHA256 sha = SHA256.Create())
                using (FileStream stream = new FileStream(
                    fullPath,
                    FileMode.Open,
                    FileAccess.Read,
                    FileShare.ReadWrite | FileShare.Delete))
                {
                    return Hex(sha.ComputeHash(stream));
                }
            }));
            methods.Add(CaptureHash("sha256-create-read-all-bytes", delegate
            {
                byte[] bytes = File.ReadAllBytes(fullPath);
                using (SHA256 sha = SHA256.Create())
                {
                    return Hex(sha.ComputeHash(bytes));
                }
            }));

            return new IdentityAuditFileFingerprintV1
            {
                capturedAtUtc = DateTime.UtcNow.ToString("o", CultureInfo.InvariantCulture),
                path = NormalizePath(fullPath),
                lengthBytes = info.Length,
                creationTimeUtc = info.CreationTimeUtc.ToString("o", CultureInfo.InvariantCulture),
                lastWriteTimeUtc = info.LastWriteTimeUtc.ToString("o", CultureInfo.InvariantCulture),
                attributes = info.Attributes.ToString(),
                fileIdentity = CaptureFileIdentity(fullPath),
                peIdentity = CapturePeIdentity(fullPath),
                fullFileHashes = methods.ToArray(),
                chunkSizeBytes = ChunkSizeBytes,
                chunkHashes = CaptureChunkHashes(fullPath, ChunkSizeBytes)
            };
        }

        private static IdentityAuditHashMethodV1 CaptureHash(string method, Func<string> compute)
        {
            IdentityAuditHashMethodV1 result = new IdentityAuditHashMethodV1 { method = method };
            try
            {
                result.sha256 = compute();
                result.succeeded = true;
            }
            catch (Exception exception)
            {
                result.succeeded = false;
                result.exactFailure = exception.GetType().FullName + ": " + exception.Message;
            }
            return result;
        }

        private static IdentityAuditChunkHashV1[] CaptureChunkHashes(string path, int chunkSize)
        {
            List<IdentityAuditChunkHashV1> chunks = new List<IdentityAuditChunkHashV1>();
            using (FileStream stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
            {
                byte[] buffer = new byte[chunkSize];
                int index = 0;
                long offset = 0;
                while (true)
                {
                    int count = 0;
                    while (count < buffer.Length)
                    {
                        int read = stream.Read(buffer, count, buffer.Length - count);
                        if (read == 0) break;
                        count += read;
                    }
                    if (count == 0) break;
                    string digest;
                    using (SHA256 sha = SHA256.Create())
                    {
                        digest = Hex(sha.ComputeHash(buffer, 0, count));
                    }
                    chunks.Add(new IdentityAuditChunkHashV1
                    {
                        chunkIndex = index,
                        offsetBytes = offset,
                        lengthBytes = count,
                        sha256 = digest
                    });
                    index++;
                    offset += count;
                    if (count < buffer.Length) break;
                }
            }
            return chunks.ToArray();
        }

        private static IdentityAuditFileIdV1 CaptureFileIdentity(string path)
        {
            IdentityAuditFileIdV1 result = new IdentityAuditFileIdV1 { normalizedPath = NormalizePath(path) };
            IntPtr handle = new IntPtr(-1);
            try
            {
                handle = CreateFileW(path, GenericReadAttributes, ShareRead | ShareWrite | ShareDelete, IntPtr.Zero, OpenExisting, 0, IntPtr.Zero);
                if (handle == new IntPtr(-1))
                {
                    throw new InvalidOperationException("CreateFileW failed with Win32 error " + Marshal.GetLastWin32Error().ToString(CultureInfo.InvariantCulture));
                }
                ByHandleFileInformation information;
                if (!GetFileInformationByHandle(handle, out information))
                {
                    throw new InvalidOperationException("GetFileInformationByHandle failed with Win32 error " + Marshal.GetLastWin32Error().ToString(CultureInfo.InvariantCulture));
                }
                StringBuilder finalPath = new StringBuilder(32768);
                uint finalLength = GetFinalPathNameByHandleW(handle, finalPath, (uint)finalPath.Capacity, 0);
                if (finalLength == 0 || finalLength >= finalPath.Capacity)
                {
                    throw new InvalidOperationException("GetFinalPathNameByHandleW failed with Win32 error " + Marshal.GetLastWin32Error().ToString(CultureInfo.InvariantCulture));
                }
                ulong fileIndex = ((ulong)information.FileIndexHigh << 32) | information.FileIndexLow;
                result.finalPath = NormalizePath(RemoveExtendedPathPrefix(finalPath.ToString()));
                result.volumeSerialHex = information.VolumeSerialNumber.ToString("x8", CultureInfo.InvariantCulture);
                result.fileIndexHex = fileIndex.ToString("x16", CultureInfo.InvariantCulture);
                result.succeeded = true;
            }
            catch (Exception exception)
            {
                result.succeeded = false;
                result.exactFailure = exception.GetType().FullName + ": " + exception.Message;
            }
            finally
            {
                if (handle != new IntPtr(-1)) CloseHandle(handle);
            }
            return result;
        }

        private static IdentityAuditPeIdentityV1 CapturePeIdentity(string path)
        {
            IdentityAuditPeIdentityV1 result = new IdentityAuditPeIdentityV1();
            try
            {
                using (FileStream stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
                using (BinaryReader reader = new BinaryReader(stream, Encoding.UTF8, false))
                {
                    Require(stream.Length >= 256, "PE file is too short.");
                    stream.Position = 0x3c;
                    int peOffset = reader.ReadInt32();
                    Require(peOffset > 0 && peOffset + 256 < stream.Length, "PE header offset is invalid.");
                    stream.Position = peOffset;
                    Require(reader.ReadUInt32() == 0x00004550, "PE signature is invalid.");
                    long optionalHeaderOffset = peOffset + 24L;
                    stream.Position = optionalHeaderOffset;
                    ushort magic = reader.ReadUInt16();
                    Require(magic == 0x10b || magic == 0x20b, "PE optional-header magic is unsupported.");
                    long checksumOffset = optionalHeaderOffset + 64L;
                    stream.Position = checksumOffset;
                    uint checksum = reader.ReadUInt32();
                    long dataDirectoryOffset = optionalHeaderOffset + (magic == 0x20b ? 112L : 96L);
                    long securityDirectoryOffset = dataDirectoryOffset + 32L;
                    stream.Position = securityDirectoryOffset;
                    uint certificateOffset = reader.ReadUInt32();
                    uint certificateSize = reader.ReadUInt32();
                    result.peHeaderOffset = peOffset;
                    result.optionalHeaderMagicHex = magic.ToString("x4", CultureInfo.InvariantCulture);
                    result.checksumFieldOffset = checksumOffset;
                    result.checksumHex = checksum.ToString("x8", CultureInfo.InvariantCulture);
                    result.securityDirectoryFieldOffset = securityDirectoryOffset;
                    result.certificateTableFileOffset = certificateOffset;
                    result.certificateTableSizeBytes = certificateSize;
                    result.succeeded = true;
                }
            }
            catch (Exception exception)
            {
                result.succeeded = false;
                result.exactFailure = exception.GetType().FullName + ": " + exception.Message;
            }
            return result;
        }

        private static bool FingerprintsEqual(IdentityAuditFileFingerprintV1 left, IdentityAuditFileFingerprintV1 right)
        {
            if (left == null || right == null || left.lengthBytes != right.lengthBytes ||
                !PathsEqual(left.path, right.path) || left.fullFileHashes == null || right.fullFileHashes == null ||
                left.fullFileHashes.Length != right.fullFileHashes.Length || left.chunkHashes == null || right.chunkHashes == null ||
                left.chunkHashes.Length != right.chunkHashes.Length)
            {
                return false;
            }
            for (int index = 0; index < left.fullFileHashes.Length; index++)
            {
                if (left.fullFileHashes[index].method != right.fullFileHashes[index].method ||
                    left.fullFileHashes[index].succeeded != right.fullFileHashes[index].succeeded ||
                    left.fullFileHashes[index].sha256 != right.fullFileHashes[index].sha256)
                {
                    return false;
                }
            }
            for (int index = 0; index < left.chunkHashes.Length; index++)
            {
                if (left.chunkHashes[index].chunkIndex != right.chunkHashes[index].chunkIndex ||
                    left.chunkHashes[index].offsetBytes != right.chunkHashes[index].offsetBytes ||
                    left.chunkHashes[index].lengthBytes != right.chunkHashes[index].lengthBytes ||
                    left.chunkHashes[index].sha256 != right.chunkHashes[index].sha256)
                {
                    return false;
                }
            }
            return left.fileIdentity != null && right.fileIdentity != null &&
                left.fileIdentity.succeeded && right.fileIdentity.succeeded &&
                left.fileIdentity.volumeSerialHex == right.fileIdentity.volumeSerialHex &&
                left.fileIdentity.fileIndexHex == right.fileIdentity.fileIndexHex;
        }

        private static string RequiredHash(IdentityAuditFileFingerprintV1 fingerprint, string method)
        {
            Require(fingerprint != null && fingerprint.fullFileHashes != null, "File fingerprint hashes are absent.");
            for (int index = 0; index < fingerprint.fullFileHashes.Length; index++)
            {
                IdentityAuditHashMethodV1 value = fingerprint.fullFileHashes[index];
                if (value.method == method)
                {
                    Require(value.succeeded && !string.IsNullOrEmpty(value.sha256), "Required file hash failed: " + method);
                    return value.sha256;
                }
            }
            throw new InvalidOperationException("Required file hash method is absent: " + method);
        }

        private static void BindRelative(string root, List<IdentityAuditFileBindingV1> bindings, string role, string relativePath, string expectedSha256)
        {
            BindAbsolute(bindings, role, Path.GetFullPath(Path.Combine(root, relativePath.Replace('/', Path.DirectorySeparatorChar))), expectedSha256, relativePath);
        }

        private static void BindAbsolute(List<IdentityAuditFileBindingV1> bindings, string role, string path, string expectedSha256)
        {
            BindAbsolute(bindings, role, Path.GetFullPath(path), expectedSha256, NormalizePath(path));
        }

        private static void BindAbsolute(List<IdentityAuditFileBindingV1> bindings, string role, string path, string expectedSha256, string displayPath)
        {
            Require(File.Exists(path), "Missing bound file: " + displayPath);
            string actual = Sha256File(path);
            FileInfo info = new FileInfo(path);
            IdentityAuditFileBindingV1 binding = new IdentityAuditFileBindingV1
            {
                role = role,
                relativePath = NormalizePath(displayPath),
                lengthBytes = info.Length,
                expectedSha256 = expectedSha256.ToLowerInvariant(),
                actualSha256 = actual,
                matched = actual == expectedSha256.ToLowerInvariant()
            };
            bindings.Add(binding);
            Require(binding.matched, "Bound-file SHA-256 mismatch: " + displayPath);
        }

        private static Dictionary<string, string> ParseArguments(string[] args)
        {
            Dictionary<string, string> parsed = new Dictionary<string, string>(StringComparer.Ordinal);
            for (int index = 0; index < args.Length; index++)
            {
                if (!args[index].StartsWith("--g14me-", StringComparison.Ordinal)) continue;
                Require(index + 1 < args.Length, "Missing value for " + args[index]);
                parsed[args[index]] = args[++index];
            }
            return parsed;
        }

        private static string Required(Dictionary<string, string> arguments, string name)
        {
            string value;
            Require(arguments.TryGetValue(name, out value) && !string.IsNullOrWhiteSpace(value), "Missing required argument " + name);
            return value;
        }

        private static string ResolveExactNewOutputDirectory(string sourceProjectRoot, string requested)
        {
            string expected = Path.GetFullPath(Path.Combine(sourceProjectRoot, ExpectedOutputRelativePath.Replace('/', Path.DirectorySeparatorChar)));
            string actual = Path.GetFullPath(requested);
            Require(string.Equals(actual, expected, StringComparison.OrdinalIgnoreCase), "Identity-probe output path is outside the authorized verification directory.");
            Require(!Directory.Exists(actual) && !File.Exists(actual), "Identity-probe output already exists; overwrite is prohibited.");
            Directory.CreateDirectory(actual);
            return actual;
        }

        private static string Sha256File(string path)
        {
            using (SHA256 sha = SHA256.Create())
            using (FileStream stream = File.OpenRead(path))
            {
                return Hex(sha.ComputeHash(stream));
            }
        }

        private static string Hex(byte[] bytes)
        {
            StringBuilder builder = new StringBuilder(bytes.Length * 2);
            for (int index = 0; index < bytes.Length; index++) builder.Append(bytes[index].ToString("x2", CultureInfo.InvariantCulture));
            return builder.ToString();
        }

        private static string NormalizePath(string path)
        {
            if (string.IsNullOrEmpty(path)) return path;
            return Path.GetFullPath(RemoveExtendedPathPrefix(path)).Replace('\\', '/');
        }

        private static string RemoveExtendedPathPrefix(string path)
        {
            if (path.StartsWith("\\\\?\\UNC\\", StringComparison.OrdinalIgnoreCase)) return "\\\\" + path.Substring(8);
            if (path.StartsWith("\\\\?\\", StringComparison.OrdinalIgnoreCase)) return path.Substring(4);
            return path;
        }

        private static bool PathsEqual(string left, string right)
        {
            if (string.IsNullOrEmpty(left) || string.IsNullOrEmpty(right)) return false;
            return string.Equals(NormalizePath(left), NormalizePath(right), StringComparison.OrdinalIgnoreCase);
        }

        private static void WriteJsonAtomic(string path, object value)
        {
            string temporary = path + ".tmp-" + Guid.NewGuid().ToString("N");
            File.WriteAllText(temporary, JsonUtility.ToJson(value, true) + Environment.NewLine, new UTF8Encoding(false));
            if (File.Exists(path)) throw new IOException("Refusing to overwrite existing receipt: " + path);
            File.Move(temporary, path);
        }

        private static void Require(bool condition, string message)
        {
            if (!condition) throw new InvalidOperationException(message);
        }

        private sealed class ZeroStream : Stream
        {
            private readonly long totalLength;
            private long position;

            public ZeroStream(long length)
            {
                if (length < 0) throw new ArgumentOutOfRangeException("length");
                totalLength = length;
            }

            public override bool CanRead { get { return true; } }
            public override bool CanSeek { get { return false; } }
            public override bool CanWrite { get { return false; } }
            public override long Length { get { return totalLength; } }
            public override long Position { get { return position; } set { throw new NotSupportedException(); } }

            public override int Read(byte[] buffer, int offset, int count)
            {
                if (position >= totalLength) return 0;
                int available = (int)Math.Min((long)count, totalLength - position);
                Array.Clear(buffer, offset, available);
                position += available;
                return available;
            }

            public override void Flush() { }
            public override long Seek(long offset, SeekOrigin origin) { throw new NotSupportedException(); }
            public override void SetLength(long value) { throw new NotSupportedException(); }
            public override void Write(byte[] buffer, int offset, int count) { throw new NotSupportedException(); }
        }
    }
}
#endif
