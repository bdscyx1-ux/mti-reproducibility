using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using DDM.Research.Gate14Re.V1;

namespace DDM.Research.Gate14ReTB.V1
{
    /// <summary>
    /// Allocation-bounded 10 Hz visual trace capture. Capture only copies the
    /// already-observed unit state into preallocated arrays. Container creation,
    /// hashing, disk I/O, and compression all occur after the measured window.
    /// </summary>
    public sealed class Gate14ReTBTraceRecorderV1
    {
        public const int MaximumCapturedFrames = 1802;

        private readonly Gate14ReTBTraceHeaderV1 header;
        private readonly IReadOnlyList<Gate14ReUnitStateV1> units;
        private readonly int unitCount;
        private readonly bool syntheticValidationOnly;
        private readonly long[] fixedTicks;
        private readonly long[] gridRevisions;
        private readonly byte[] eventMasks;
        private readonly float[] positions;
        private readonly byte[] arrived;
        private int captured;

        public int CapturedCount { get { return captured; } }
        public bool BufferPreallocated { get { return fixedTicks != null && positions != null && arrived != null; } }

        public Gate14ReTBTraceRecorderV1(Gate14ReTBTraceHeaderV1 header, IReadOnlyList<Gate14ReUnitStateV1> units)
        {
            this.header = header ?? throw new ArgumentNullException("header");
            this.units = units ?? throw new ArgumentNullException("units");
            if (units.Count < 1 || units.Count > Gate14ReTBProtocolV1.MaximumSpawnCount || header.unitCount != units.Count)
                throw new InvalidOperationException("Trace unit cardinality is invalid.");
            unitCount = units.Count;
            fixedTicks = new long[MaximumCapturedFrames];
            gridRevisions = new long[MaximumCapturedFrames];
            eventMasks = new byte[MaximumCapturedFrames];
            positions = new float[checked(MaximumCapturedFrames * unitCount * 3)];
            arrived = new byte[checked(MaximumCapturedFrames * unitCount)];
        }

        public Gate14ReTBTraceRecorderV1(Gate14ReTBTraceHeaderV1 header, int syntheticUnitCount)
        {
            this.header = header ?? throw new ArgumentNullException("header");
            if (syntheticUnitCount < 1 || syntheticUnitCount > Gate14ReTBProtocolV1.MaximumSpawnCount || header.unitCount != syntheticUnitCount || header.sampleId == null || !header.sampleId.StartsWith("SYNTHETIC-", StringComparison.Ordinal))
                throw new InvalidOperationException("Synthetic trace validation constructor requires a SYNTHETIC sample and valid unit count.");
            unitCount = syntheticUnitCount;
            syntheticValidationOnly = true;
            fixedTicks = new long[MaximumCapturedFrames];
            gridRevisions = new long[MaximumCapturedFrames];
            eventMasks = new byte[MaximumCapturedFrames];
            positions = new float[checked(MaximumCapturedFrames * unitCount * 3)];
            arrived = new byte[checked(MaximumCapturedFrames * unitCount)];
        }

        public void Capture(long fixedTick, long gridRevision, int appliedEventCount)
        {
            if (fixedTick < 0L || fixedTick >= Gate14ReTBProtocolV1.MovementCapTicks)
                throw new ArgumentOutOfRangeException("fixedTick");
            if (captured > 0 && fixedTick <= fixedTicks[captured - 1])
                throw new InvalidOperationException("Trace ticks must be strictly increasing.");
            if (captured >= MaximumCapturedFrames) throw new InvalidOperationException("Preallocated trace frame capacity was exceeded.");
            if (appliedEventCount < 0 || appliedEventCount > 5) throw new InvalidOperationException("Trace event count is invalid.");

            fixedTicks[captured] = fixedTick;
            gridRevisions[captured] = gridRevision;
            eventMasks[captured] = appliedEventCount == 0 ? (byte)0 : (byte)((1 << appliedEventCount) - 1);
            int positionBase = checked(captured * unitCount * 3);
            int arrivalBase = checked(captured * unitCount);
            for (int index = 0; index < unitCount; index++)
            {
                Gate14ReUnitStateV1 state = units[index];
                int offset = positionBase + index * 3;
                positions[offset] = state.Position.x;
                positions[offset + 1] = state.Position.y;
                positions[offset + 2] = state.Position.z;
                arrived[arrivalBase + index] = state.State == Gate14ReUnitTerminalStateV1.Arrived ? (byte)1 : (byte)0;
            }
            captured++;
        }

        public void CaptureSyntheticForValidation(long fixedTick, long gridRevision, int appliedEventCount, UnityEngine.Vector3[] syntheticPositions, bool[] syntheticArrivals)
        {
            if (!syntheticValidationOnly || units != null) throw new InvalidOperationException("Synthetic trace capture is forbidden on a production recorder.");
            if (syntheticPositions == null || syntheticArrivals == null || syntheticPositions.Length != unitCount || syntheticArrivals.Length != unitCount)
                throw new InvalidOperationException("Synthetic trace arrays have invalid cardinality.");
            BeginCapture(fixedTick, gridRevision, appliedEventCount);
            int positionBase = checked(captured * unitCount * 3);
            int arrivalBase = checked(captured * unitCount);
            for (int index = 0; index < unitCount; index++)
            {
                int offset = positionBase + index * 3;
                positions[offset] = syntheticPositions[index].x;
                positions[offset + 1] = syntheticPositions[index].y;
                positions[offset + 2] = syntheticPositions[index].z;
                arrived[arrivalBase + index] = syntheticArrivals[index] ? (byte)1 : (byte)0;
            }
            captured++;
        }

        private void BeginCapture(long fixedTick, long gridRevision, int appliedEventCount)
        {
            if (fixedTick < 0L || fixedTick >= Gate14ReTBProtocolV1.MovementCapTicks) throw new ArgumentOutOfRangeException("fixedTick");
            if (captured > 0 && fixedTick <= fixedTicks[captured - 1]) throw new InvalidOperationException("Trace ticks must be strictly increasing.");
            if (captured >= MaximumCapturedFrames) throw new InvalidOperationException("Preallocated trace frame capacity was exceeded.");
            if (appliedEventCount < 0 || appliedEventCount > 5) throw new InvalidOperationException("Trace event count is invalid.");
            fixedTicks[captured] = fixedTick;
            gridRevisions[captured] = gridRevision;
            eventMasks[captured] = appliedEventCount == 0 ? (byte)0 : (byte)((1 << appliedEventCount) - 1);
        }

        public Gate14ReTBTraceWriteResultV1 Flush(string path)
        {
            if (captured < 1) throw new InvalidOperationException("Trace contains no captured frame.");
            if (File.Exists(path) || File.Exists(path + ".tmp")) throw new IOException("Trace overwrite is forbidden: " + path);
            string directory = Path.GetDirectoryName(path);
            if (!Directory.Exists(directory)) throw new DirectoryNotFoundException("Trace output directory is missing: " + directory);

            byte[] headerBytes = Encoding.UTF8.GetBytes(UnityEngine.JsonUtility.ToJson(header, false));
            List<byte[]> digests = new List<byte[]>(captured + 1);
            string temporary = path + ".tmp";
            try
            {
                using (FileStream stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None))
                using (BinaryWriter writer = new BinaryWriter(stream, Encoding.UTF8, true))
                {
                    writer.Write(Encoding.ASCII.GetBytes("G14RTBTR"));
                    writer.Write(1);
                    writer.Write(captured + 1);
                    WriteChunk(writer, 0, -1L, headerBytes, digests);
                    for (int frame = 0; frame < captured; frame++)
                    {
                        byte[] frameBytes = BuildFrameBytes(frame);
                        WriteChunk(writer, 1, fixedTicks[frame], frameBytes, digests);
                    }
                    byte[] root = ComputeMerkleRoot(digests);
                    writer.Write(root);
                    writer.Flush();
                    stream.Flush(true);
                }
                File.Move(temporary, path);
            }
            catch
            {
                try { if (File.Exists(temporary)) File.Delete(temporary); } catch { }
                throw;
            }

            return new Gate14ReTBTraceWriteResultV1
            {
                traceRawSha256 = Sha256File(path),
                traceMerkleRootSha256 = Hex(ComputeMerkleRoot(digests)),
                traceChunkCount = captured + 1,
                traceCapturedTickCount = captured,
                traceRawBytes = new FileInfo(path).Length
            };
        }

        private byte[] BuildFrameBytes(int frame)
        {
            using (MemoryStream stream = new MemoryStream(checked(9 + unitCount * 13)))
            using (BinaryWriter writer = new BinaryWriter(stream, Encoding.UTF8, true))
            {
                writer.Write(gridRevisions[frame]);
                writer.Write(eventMasks[frame]);
                int positionBase = checked(frame * unitCount * 3);
                int arrivalBase = checked(frame * unitCount);
                for (int index = 0; index < unitCount; index++)
                {
                    int offset = positionBase + index * 3;
                    writer.Write(positions[offset]);
                    writer.Write(positions[offset + 1]);
                    writer.Write(positions[offset + 2]);
                    writer.Write(arrived[arrivalBase + index]);
                }
                writer.Flush();
                byte[] result = stream.ToArray();
                if (result.Length != 9 + unitCount * 13) throw new InvalidOperationException("Trace frame serialization cardinality mismatch.");
                return result;
            }
        }

        private static void WriteChunk(BinaryWriter writer, int type, long fixedTick, byte[] data, List<byte[]> digests)
        {
            byte[] digest;
            using (SHA256 sha = SHA256.Create()) digest = sha.ComputeHash(data);
            writer.Write(type);
            writer.Write(fixedTick);
            writer.Write(data.Length);
            writer.Write(digest);
            writer.Write(data);
            digests.Add(digest);
        }

        private static byte[] ComputeMerkleRoot(IReadOnlyList<byte[]> source)
        {
            if (source == null || source.Count == 0) throw new InvalidOperationException("Trace Merkle tree is empty.");
            List<byte[]> level = new List<byte[]>(source.Count);
            for (int index = 0; index < source.Count; index++) level.Add((byte[])source[index].Clone());
            while (level.Count > 1)
            {
                if ((level.Count & 1) != 0) level.Add((byte[])level[level.Count - 1].Clone());
                List<byte[]> next = new List<byte[]>(level.Count / 2);
                for (int index = 0; index < level.Count; index += 2)
                {
                    byte[] pair = new byte[64];
                    Buffer.BlockCopy(level[index], 0, pair, 0, 32);
                    Buffer.BlockCopy(level[index + 1], 0, pair, 32, 32);
                    using (SHA256 sha = SHA256.Create()) next.Add(sha.ComputeHash(pair));
                }
                level = next;
            }
            return level[0];
        }

        private static string Sha256File(string path)
        {
            using (FileStream stream = File.OpenRead(path))
            using (SHA256 sha = SHA256.Create()) return Hex(sha.ComputeHash(stream));
        }

        private static string Hex(byte[] bytes)
        {
            StringBuilder builder = new StringBuilder(bytes.Length * 2);
            for (int index = 0; index < bytes.Length; index++) builder.Append(bytes[index].ToString("x2", CultureInfo.InvariantCulture));
            return builder.ToString();
        }
    }

    public sealed class Gate14ReTBTraceWriteResultV1
    {
        public string traceRawSha256;
        public string traceMerkleRootSha256;
        public int traceChunkCount;
        public int traceCapturedTickCount;
        public long traceRawBytes;
    }
}
