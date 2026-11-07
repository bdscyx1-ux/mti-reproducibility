using System;
using System.Collections.Generic;
using System.Globalization;
using System.Runtime.InteropServices;

namespace DDM.Research.MQ.V1
{
    [Serializable]
    public sealed class WindowsCpuSetV1
    {
        public int cpuSetId;
        public int group;
        public int logicalProcessorIndex;
        public int coreIndex;
        public int lastLevelCacheIndex;
        public int numaNodeIndex;
        public int efficiencyClass;
        public bool parked;
        public string l3DomainId;
        public long l3CacheBytes;
        public bool selectedPhysicalCoreSibling;
        public int physicalCoreOrdinalWithinDomain;
    }

    [Serializable]
    public sealed class WindowsL3DomainV1
    {
        public string domainId;
        public string role;
        public string roleEvidence;
        public int group;
        public string affinityMaskHex;
        public long cacheBytes;
        public int logicalProcessorCount;
        public int physicalCoreCount;
    }

    [Serializable]
    public sealed class WindowsCpuTopologySnapshotV1
    {
        public string schema;
        public string capturedAtUtc;
        public string processorName;
        public int pointerSizeBytes;
        public int logicalProcessorCount;
        public int selectedPhysicalCoreCount;
        public WindowsL3DomainV1[] l3Domains = new WindowsL3DomainV1[0];
        public WindowsCpuSetV1[] cpuSets = new WindowsCpuSetV1[0];
    }

    [Serializable]
    public sealed class CpuWorkerBindingV1
    {
        public int workerIndex;
        public string planId;
        public string topologyRole;
        public int cpuSetId;
        public int group;
        public int logicalProcessorIndex;
        public int coreIndex;
        public int lastLevelCacheIndex;
        public string l3DomainId;
        public long l3CacheBytes;
    }

    [Serializable]
    public sealed class CpuAffinityPlanV1
    {
        public string schema;
        public string planId;
        public string topologyRole;
        public int workerCount;
        public bool usesSmtSibling;
        public bool spansMultipleL3Domains;
        public CpuWorkerBindingV1[] workers = new CpuWorkerBindingV1[0];
    }

    [Serializable]
    public sealed class CurrentProcessorObservationV1
    {
        public int group;
        public int logicalProcessorIndex;
    }

    /// <summary>
    /// Windows-only topology and hard CPU-set binding used by the managed MQ study.
    /// One logical processor is selected per physical core, so the primary matrix
    /// never silently introduces SMT contention.
    /// </summary>
    public static class WindowsCpuTopologyV1
    {
        public const string LargeL3Role = "LARGE_L3_CCD";
        public const string HighFrequencyRole = "HIGH_FREQUENCY_CCD";
        public const string DualCcdBalancedRole = "DUAL_CCD_BALANCED";

        private const int RelationCache = 2;
        private const int ErrorInsufficientBuffer = 122;

        public static WindowsCpuTopologySnapshotV1 Capture()
        {
            Require(RuntimeInformation.IsOSPlatform(OSPlatform.Windows), "MQ CPU topology capture requires Windows.");
            Require(IntPtr.Size == 8, "MQ CPU topology capture is frozen to a 64-bit Unity process.");

            List<L3CacheRecord> l3Records = ReadL3CacheRecords();
            List<WindowsCpuSetV1> cpuSets = ReadCpuSets();
            Require(l3Records.Count == 2, "Expected exactly two L3 cache domains for the frozen dual-CCD design, observed " + l3Records.Count + ".");

            for (int index = 0; index < cpuSets.Count; index++)
            {
                WindowsCpuSetV1 cpuSet = cpuSets[index];
                L3CacheRecord match = null;
                ulong bit = 1UL << cpuSet.logicalProcessorIndex;
                for (int cacheIndex = 0; cacheIndex < l3Records.Count; cacheIndex++)
                {
                    L3CacheRecord candidate = l3Records[cacheIndex];
                    if (candidate.Group == cpuSet.group && (candidate.Mask & bit) != 0UL)
                    {
                        Require(match == null, "A logical processor maps to more than one L3 domain.");
                        match = candidate;
                    }
                }
                Require(match != null, "No L3 cache domain contains logical processor " + cpuSet.group + ":" + cpuSet.logicalProcessorIndex + ".");
                cpuSet.l3DomainId = match.DomainId;
                cpuSet.l3CacheBytes = checked((long)match.CacheBytes);
            }

            MarkOneSiblingPerPhysicalCore(cpuSets);

            l3Records.Sort(delegate(L3CacheRecord left, L3CacheRecord right)
            {
                int cacheComparison = right.CacheBytes.CompareTo(left.CacheBytes);
                if (cacheComparison != 0) return cacheComparison;
                int groupComparison = left.Group.CompareTo(right.Group);
                return groupComparison != 0 ? groupComparison : left.Mask.CompareTo(right.Mask);
            });
            Require(l3Records[0].CacheBytes > l3Records[1].CacheBytes,
                "The frozen LARGE_L3_CCD versus HIGH_FREQUENCY_CCD design requires unequal detected L3 capacities.");

            WindowsL3DomainV1[] domains = new WindowsL3DomainV1[2];
            for (int index = 0; index < l3Records.Count; index++)
            {
                L3CacheRecord record = l3Records[index];
                string role = index == 0 ? LargeL3Role : HighFrequencyRole;
                int logicalCount = 0;
                int physicalCount = 0;
                for (int cpuIndex = 0; cpuIndex < cpuSets.Count; cpuIndex++)
                {
                    if (cpuSets[cpuIndex].l3DomainId != record.DomainId) continue;
                    logicalCount++;
                    if (cpuSets[cpuIndex].selectedPhysicalCoreSibling) physicalCount++;
                }
                domains[index] = new WindowsL3DomainV1
                {
                    domainId = record.DomainId,
                    role = role,
                    roleEvidence = index == 0
                        ? "DETECTED_LARGEST_L3_DOMAIN"
                        : "DETECTED_SMALLER_L3_DOMAIN_WITH_USER_FROZEN_HIGH_FREQUENCY_ROLE",
                    group = record.Group,
                    affinityMaskHex = "0x" + record.Mask.ToString("x16", CultureInfo.InvariantCulture),
                    cacheBytes = checked((long)record.CacheBytes),
                    logicalProcessorCount = logicalCount,
                    physicalCoreCount = physicalCount
                };
            }

            Require(domains[0].physicalCoreCount == 8 && domains[1].physicalCoreCount == 8,
                "The frozen design requires exactly eight physical cores in each L3/CCD domain.");

            cpuSets.Sort(CompareCpuSets);
            return new WindowsCpuTopologySnapshotV1
            {
                schema = "gate14re-mq-windows-cpu-topology-v1",
                capturedAtUtc = DateTimeOffset.UtcNow.ToString("o"),
                processorName = ReadProcessorName(),
                pointerSizeBytes = IntPtr.Size,
                logicalProcessorCount = cpuSets.Count,
                selectedPhysicalCoreCount = CountSelectedPhysicalCores(cpuSets),
                l3Domains = domains,
                cpuSets = cpuSets.ToArray()
            };
        }

        public static CpuAffinityPlanV1 CreatePlan(
            WindowsCpuTopologySnapshotV1 topology,
            string planId,
            string topologyRole,
            int workerCount)
        {
            if (topology == null) throw new ArgumentNullException("topology");
            if (string.IsNullOrWhiteSpace(planId)) throw new ArgumentException("Plan id is required.", "planId");
            if (workerCount <= 0) throw new ArgumentOutOfRangeException("workerCount");

            List<WindowsCpuSetV1> large = SelectedCpuSetsForRole(topology, LargeL3Role);
            List<WindowsCpuSetV1> high = SelectedCpuSetsForRole(topology, HighFrequencyRole);
            List<WindowsCpuSetV1> selected = new List<WindowsCpuSetV1>();

            if (topologyRole == LargeL3Role)
            {
                Require(workerCount <= large.Count, "Worker count exceeds the physical-core count of LARGE_L3_CCD.");
                for (int index = 0; index < workerCount; index++) selected.Add(large[index]);
            }
            else if (topologyRole == HighFrequencyRole)
            {
                Require(workerCount <= high.Count, "Worker count exceeds the physical-core count of HIGH_FREQUENCY_CCD.");
                for (int index = 0; index < workerCount; index++) selected.Add(high[index]);
            }
            else if (topologyRole == DualCcdBalancedRole)
            {
                Require(workerCount == 8 || workerCount == 16,
                    "The frozen balanced dual-CCD bridge permits only MQ-8 (4+4) or MQ-16 (8+8).");
                int perDomain = workerCount / 2;
                Require(perDomain <= large.Count && perDomain <= high.Count, "Insufficient physical cores for a balanced dual-CCD plan.");
                for (int index = 0; index < perDomain; index++)
                {
                    selected.Add(large[index]);
                    selected.Add(high[index]);
                }
            }
            else
            {
                throw new InvalidOperationException("Unsupported topology role: " + topologyRole);
            }

            CpuWorkerBindingV1[] workers = new CpuWorkerBindingV1[selected.Count];
            HashSet<string> physicalCores = new HashSet<string>(StringComparer.Ordinal);
            HashSet<string> domains = new HashSet<string>(StringComparer.Ordinal);
            for (int index = 0; index < selected.Count; index++)
            {
                WindowsCpuSetV1 cpuSet = selected[index];
                Require(cpuSet.selectedPhysicalCoreSibling, "Affinity plan attempted to use a non-primary SMT sibling.");
                Require(physicalCores.Add(cpuSet.group + ":" + cpuSet.coreIndex), "Affinity plan reused a physical core.");
                domains.Add(cpuSet.l3DomainId);
                workers[index] = new CpuWorkerBindingV1
                {
                    workerIndex = index,
                    planId = planId,
                    topologyRole = topologyRole,
                    cpuSetId = cpuSet.cpuSetId,
                    group = cpuSet.group,
                    logicalProcessorIndex = cpuSet.logicalProcessorIndex,
                    coreIndex = cpuSet.coreIndex,
                    lastLevelCacheIndex = cpuSet.lastLevelCacheIndex,
                    l3DomainId = cpuSet.l3DomainId,
                    l3CacheBytes = cpuSet.l3CacheBytes
                };
            }

            return new CpuAffinityPlanV1
            {
                schema = "gate14re-mq-cpu-affinity-plan-v1",
                planId = planId,
                topologyRole = topologyRole,
                workerCount = workerCount,
                usesSmtSibling = false,
                spansMultipleL3Domains = domains.Count > 1,
                workers = workers
            };
        }

        public static void BindCurrentThread(CpuWorkerBindingV1 binding)
        {
            if (binding == null) throw new ArgumentNullException("binding");
            IntPtr idBuffer = Marshal.AllocHGlobal(sizeof(uint));
            try
            {
                Marshal.WriteInt32(idBuffer, binding.cpuSetId);
                if (!SetThreadSelectedCpuSets(GetCurrentThread(), idBuffer, 1U))
                {
                    throw new InvalidOperationException("SetThreadSelectedCpuSets failed with Win32 error " + Marshal.GetLastWin32Error() + ".");
                }
                // The selected CPU-set constraint is effective immediately, but the
                // caller can still be observed on its previous processor until the
                // next scheduling point. Yield once before fail-closed verification.
                System.Threading.Thread.Yield();
                CurrentProcessorObservationV1 observed = CaptureCurrentProcessor();
                Require(observed.group == binding.group && observed.logicalProcessorIndex == binding.logicalProcessorIndex,
                    "The affinity-bound worker executed on an unexpected logical processor immediately after binding.");
            }
            finally
            {
                Marshal.FreeHGlobal(idBuffer);
            }
        }

        public static void ClearCurrentThreadBinding()
        {
            if (!SetThreadSelectedCpuSets(GetCurrentThread(), IntPtr.Zero, 0U))
            {
                throw new InvalidOperationException("Clearing selected CPU sets failed with Win32 error " + Marshal.GetLastWin32Error() + ".");
            }
        }

        public static CurrentProcessorObservationV1 CaptureCurrentProcessor()
        {
            ProcessorNumber number;
            GetCurrentProcessorNumberEx(out number);
            return new CurrentProcessorObservationV1
            {
                group = number.Group,
                logicalProcessorIndex = number.Number
            };
        }

        public static long CaptureCurrentThreadCpuTime100Nanoseconds()
        {
            FileTime creation;
            FileTime exit;
            FileTime kernel;
            FileTime user;
            if (!GetThreadTimes(GetCurrentThread(), out creation, out exit, out kernel, out user))
            {
                throw new InvalidOperationException("GetThreadTimes failed with Win32 error " + Marshal.GetLastWin32Error() + ".");
            }
            return checked((long)(ToUInt64(kernel) + ToUInt64(user)));
        }

        private static List<WindowsCpuSetV1> ReadCpuSets()
        {
            uint returnedLength;
            bool initial = GetSystemCpuSetInformation(IntPtr.Zero, 0U, out returnedLength, IntPtr.Zero, 0U);
            int initialError = Marshal.GetLastWin32Error();
            Require((!initial && initialError == ErrorInsufficientBuffer) || (initial && returnedLength > 0U),
                "GetSystemCpuSetInformation length query failed with Win32 error " + initialError + ".");
            Require(returnedLength > 0U, "GetSystemCpuSetInformation returned an empty topology buffer.");

            IntPtr buffer = Marshal.AllocHGlobal(checked((int)returnedLength));
            try
            {
                uint actualLength;
                if (!GetSystemCpuSetInformation(buffer, returnedLength, out actualLength, IntPtr.Zero, 0U))
                {
                    throw new InvalidOperationException("GetSystemCpuSetInformation failed with Win32 error " + Marshal.GetLastWin32Error() + ".");
                }
                Require(actualLength <= returnedLength, "CPU-set topology length grew during capture.");
                List<WindowsCpuSetV1> result = new List<WindowsCpuSetV1>();
                int offset = 0;
                while (offset < actualLength)
                {
                    IntPtr item = IntPtr.Add(buffer, offset);
                    int size = Marshal.ReadInt32(item, 0);
                    int type = Marshal.ReadInt32(item, 4);
                    Require(size >= 24 && offset + size <= actualLength, "Invalid SYSTEM_CPU_SET_INFORMATION record size.");
                    if (type == 0)
                    {
                        int flags = Marshal.ReadByte(item, 19);
                        result.Add(new WindowsCpuSetV1
                        {
                            cpuSetId = Marshal.ReadInt32(item, 8),
                            group = (ushort)Marshal.ReadInt16(item, 12),
                            logicalProcessorIndex = Marshal.ReadByte(item, 14),
                            coreIndex = Marshal.ReadByte(item, 15),
                            lastLevelCacheIndex = Marshal.ReadByte(item, 16),
                            numaNodeIndex = Marshal.ReadByte(item, 17),
                            efficiencyClass = Marshal.ReadByte(item, 18),
                            parked = (flags & 1) != 0,
                            physicalCoreOrdinalWithinDomain = -1
                        });
                    }
                    offset += size;
                }
                Require(result.Count == Environment.ProcessorCount,
                    "CPU-set cardinality does not match Environment.ProcessorCount: " + result.Count + " versus " + Environment.ProcessorCount + ".");
                return result;
            }
            finally
            {
                Marshal.FreeHGlobal(buffer);
            }
        }

        private static List<L3CacheRecord> ReadL3CacheRecords()
        {
            uint returnedLength = 0U;
            bool initial = GetLogicalProcessorInformationEx(RelationCache, IntPtr.Zero, ref returnedLength);
            int initialError = Marshal.GetLastWin32Error();
            Require((!initial && initialError == ErrorInsufficientBuffer) || (initial && returnedLength > 0U),
                "GetLogicalProcessorInformationEx length query failed with Win32 error " + initialError + ".");
            Require(returnedLength > 0U, "GetLogicalProcessorInformationEx returned an empty cache buffer.");

            IntPtr buffer = Marshal.AllocHGlobal(checked((int)returnedLength));
            try
            {
                if (!GetLogicalProcessorInformationEx(RelationCache, buffer, ref returnedLength))
                {
                    throw new InvalidOperationException("GetLogicalProcessorInformationEx failed with Win32 error " + Marshal.GetLastWin32Error() + ".");
                }
                List<L3CacheRecord> result = new List<L3CacheRecord>();
                int offset = 0;
                while (offset < returnedLength)
                {
                    IntPtr item = IntPtr.Add(buffer, offset);
                    int relationship = Marshal.ReadInt32(item, 0);
                    int size = Marshal.ReadInt32(item, 4);
                    Require(size >= 56 && offset + size <= returnedLength, "Invalid SYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX cache record size.");
                    if (relationship == RelationCache)
                    {
                        int level = Marshal.ReadByte(item, 8);
                        int cacheType = Marshal.ReadInt32(item, 16);
                        if (level == 3 && (cacheType == 0 || cacheType == 2))
                        {
                            uint cacheBytes = unchecked((uint)Marshal.ReadInt32(item, 12));
                            ulong mask = unchecked((ulong)Marshal.ReadInt64(item, 40));
                            int group = (ushort)Marshal.ReadInt16(item, 48);
                            Require(mask != 0UL && cacheBytes > 0U, "Observed an empty L3 cache relationship.");
                            result.Add(new L3CacheRecord
                            {
                                Group = group,
                                Mask = mask,
                                CacheBytes = cacheBytes,
                                DomainId = "G" + group.ToString(CultureInfo.InvariantCulture) + "-M" + mask.ToString("x16", CultureInfo.InvariantCulture)
                            });
                        }
                    }
                    offset += size;
                }
                return result;
            }
            finally
            {
                Marshal.FreeHGlobal(buffer);
            }
        }

        private static void MarkOneSiblingPerPhysicalCore(List<WindowsCpuSetV1> cpuSets)
        {
            Dictionary<string, List<WindowsCpuSetV1>> byCore = new Dictionary<string, List<WindowsCpuSetV1>>(StringComparer.Ordinal);
            for (int index = 0; index < cpuSets.Count; index++)
            {
                WindowsCpuSetV1 cpuSet = cpuSets[index];
                string key = cpuSet.group + ":" + cpuSet.coreIndex + ":" + cpuSet.l3DomainId;
                List<WindowsCpuSetV1> siblings;
                if (!byCore.TryGetValue(key, out siblings))
                {
                    siblings = new List<WindowsCpuSetV1>();
                    byCore.Add(key, siblings);
                }
                siblings.Add(cpuSet);
            }

            Dictionary<string, List<WindowsCpuSetV1>> selectedByDomain = new Dictionary<string, List<WindowsCpuSetV1>>(StringComparer.Ordinal);
            foreach (KeyValuePair<string, List<WindowsCpuSetV1>> pair in byCore)
            {
                pair.Value.Sort(CompareCpuSets);
                WindowsCpuSetV1 selected = pair.Value[0];
                selected.selectedPhysicalCoreSibling = true;
                List<WindowsCpuSetV1> domain;
                if (!selectedByDomain.TryGetValue(selected.l3DomainId, out domain))
                {
                    domain = new List<WindowsCpuSetV1>();
                    selectedByDomain.Add(selected.l3DomainId, domain);
                }
                domain.Add(selected);
            }

            foreach (KeyValuePair<string, List<WindowsCpuSetV1>> pair in selectedByDomain)
            {
                pair.Value.Sort(CompareCpuSets);
                for (int index = 0; index < pair.Value.Count; index++) pair.Value[index].physicalCoreOrdinalWithinDomain = index;
            }
        }

        private static List<WindowsCpuSetV1> SelectedCpuSetsForRole(WindowsCpuTopologySnapshotV1 topology, string role)
        {
            string domainId = null;
            for (int index = 0; index < topology.l3Domains.Length; index++)
            {
                if (topology.l3Domains[index].role == role) domainId = topology.l3Domains[index].domainId;
            }
            Require(domainId != null, "Topology snapshot does not define role " + role + ".");
            List<WindowsCpuSetV1> result = new List<WindowsCpuSetV1>();
            for (int index = 0; index < topology.cpuSets.Length; index++)
            {
                WindowsCpuSetV1 cpuSet = topology.cpuSets[index];
                if (cpuSet.l3DomainId == domainId && cpuSet.selectedPhysicalCoreSibling) result.Add(cpuSet);
            }
            result.Sort(CompareCpuSets);
            return result;
        }

        private static int CountSelectedPhysicalCores(List<WindowsCpuSetV1> cpuSets)
        {
            int count = 0;
            for (int index = 0; index < cpuSets.Count; index++) if (cpuSets[index].selectedPhysicalCoreSibling) count++;
            return count;
        }

        private static int CompareCpuSets(WindowsCpuSetV1 left, WindowsCpuSetV1 right)
        {
            int groupComparison = left.group.CompareTo(right.group);
            if (groupComparison != 0) return groupComparison;
            int coreComparison = left.coreIndex.CompareTo(right.coreIndex);
            if (coreComparison != 0) return coreComparison;
            int logicalComparison = left.logicalProcessorIndex.CompareTo(right.logicalProcessorIndex);
            return logicalComparison != 0 ? logicalComparison : left.cpuSetId.CompareTo(right.cpuSetId);
        }

        private static string ReadProcessorName()
        {
            // Keep the runtime assembly free of Microsoft.Win32.Registry, which
            // Unity's .NET Standard profile does not reference by default. The
            // processor string is descriptive metadata only; topology and hard
            // binding are established exclusively by the native CPU-set APIs.
            return Environment.GetEnvironmentVariable("PROCESSOR_IDENTIFIER") ?? string.Empty;
        }

        private static ulong ToUInt64(FileTime value)
        {
            return ((ulong)value.HighDateTime << 32) | value.LowDateTime;
        }

        private static void Require(bool condition, string message)
        {
            if (!condition) throw new InvalidOperationException(message);
        }

        private sealed class L3CacheRecord
        {
            public int Group;
            public ulong Mask;
            public uint CacheBytes;
            public string DomainId;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct ProcessorNumber
        {
            public ushort Group;
            public byte Number;
            public byte Reserved;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct FileTime
        {
            public uint LowDateTime;
            public uint HighDateTime;
        }

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GetSystemCpuSetInformation(
            IntPtr information,
            uint bufferLength,
            out uint returnedLength,
            IntPtr process,
            uint flags);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GetLogicalProcessorInformationEx(
            int relationshipType,
            IntPtr buffer,
            ref uint returnedLength);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool SetThreadSelectedCpuSets(
            IntPtr thread,
            IntPtr cpuSetIds,
            uint cpuSetIdCount);

        [DllImport("kernel32.dll")]
        private static extern IntPtr GetCurrentThread();

        [DllImport("kernel32.dll")]
        private static extern void GetCurrentProcessorNumberEx(out ProcessorNumber processorNumber);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GetThreadTimes(
            IntPtr thread,
            out FileTime creationTime,
            out FileTime exitTime,
            out FileTime kernelTime,
            out FileTime userTime);
    }
}
