using System;
using System.Collections.Concurrent;
using System.Globalization;
using System.IO;
using System.Text;
using System.Threading;
using UnityEngine;

namespace DDM.Research.Logging
{
    public enum ExperimentLogFileMode { CreateNew, Append }

    public interface IExperimentLogSink : IDisposable
    {
        string FilePath { get; }
        long EnqueuedCount { get; }
        long WrittenCount { get; }
        void Enqueue<T>(string recordType, string runId, T payload);
        void Flush(TimeSpan timeout);
    }

    public sealed class JsonlExperimentLogger : IExperimentLogSink
    {
        public const int SchemaVersion = 1;
        private readonly BlockingCollection<string> queue;
        private readonly StreamWriter writer;
        private readonly Thread worker;
        private readonly TimeSpan disposeTimeout;
        private long sequence;
        private long enqueued;
        private long written;
        private long flushed;
        private int disposing;
        private volatile Exception workerError;

        public string FilePath { get; private set; }
        public long EnqueuedCount { get { return Interlocked.Read(ref enqueued); } }
        public long WrittenCount { get { return Interlocked.Read(ref written); } }

        public JsonlExperimentLogger(string filePath, ExperimentLogFileMode mode = ExperimentLogFileMode.CreateNew, int capacity = 65536, int disposeTimeoutMilliseconds = 10000)
        {
            if (string.IsNullOrWhiteSpace(filePath)) throw new ArgumentException("Output path is required.", "filePath");
            if (capacity <= 0) throw new ArgumentOutOfRangeException("capacity");
            if (disposeTimeoutMilliseconds <= 0) throw new ArgumentOutOfRangeException("disposeTimeoutMilliseconds");

            FilePath = Path.GetFullPath(filePath);
            string directory = Path.GetDirectoryName(FilePath);
            if (!string.IsNullOrEmpty(directory)) Directory.CreateDirectory(directory);

            FileMode fileMode = mode == ExperimentLogFileMode.Append ? FileMode.Append : FileMode.CreateNew;
            FileStream stream = new FileStream(FilePath, fileMode, FileAccess.Write, FileShare.Read, 65536, FileOptions.SequentialScan);
            writer = new StreamWriter(stream, new UTF8Encoding(false), 65536);
            queue = new BlockingCollection<string>(new ConcurrentQueue<string>(), capacity);
            disposeTimeout = TimeSpan.FromMilliseconds(disposeTimeoutMilliseconds);
            worker = new Thread(WriterLoop) { IsBackground = true, Name = "DDM JSONL Writer" };
            worker.Start();
        }

        public void Enqueue<T>(string recordType, string runId, T payload)
        {
            EnsureAccepting();
            if (string.IsNullOrWhiteSpace(recordType)) throw new ArgumentException("Record type is required.", "recordType");
            if (string.IsNullOrWhiteSpace(runId)) throw new ArgumentException("Run id is required.", "runId");
            string payloadJson = ReferenceEquals(payload, null) ? "null" : JsonUtility.ToJson(payload, false);
            long itemSequence = Interlocked.Increment(ref sequence) - 1;
            string line = BuildEnvelope(recordType, runId, itemSequence, payloadJson);
            if (!queue.TryAdd(line)) throw new InvalidOperationException("Experiment log queue is full or closed.");
            Interlocked.Increment(ref enqueued);
        }

        public void Flush(TimeSpan timeout)
        {
            if (timeout <= TimeSpan.Zero) throw new ArgumentOutOfRangeException("timeout");
            long target = EnqueuedCount;
            DateTime deadline = DateTime.UtcNow.Add(timeout);
            while (Interlocked.Read(ref flushed) < target)
            {
                ThrowIfWorkerFailed();
                if (DateTime.UtcNow >= deadline) throw new TimeoutException("Timed out flushing experiment log.");
                Thread.Sleep(1);
            }
        }

        public void Dispose()
        {
            if (Interlocked.Exchange(ref disposing, 1) != 0) return;
            queue.CompleteAdding();
            if (!worker.Join(disposeTimeout)) throw new TimeoutException("Experiment log writer did not stop.");
            queue.Dispose();
            ThrowIfWorkerFailed();
        }

        private void WriterLoop()
        {
            try
            {
                string line;
                while (!queue.IsCompleted)
                {
                    if (!queue.TryTake(out line, 50)) continue;
                    writer.WriteLine(line);
                    Interlocked.Increment(ref written);
                    if (queue.Count == 0)
                    {
                        writer.Flush();
                        Interlocked.Exchange(ref flushed, WrittenCount);
                    }
                }
                writer.Flush();
                Interlocked.Exchange(ref flushed, WrittenCount);
            }
            catch (Exception exception) { workerError = exception; }
            finally { writer.Dispose(); }
        }

        private void EnsureAccepting()
        {
            ThrowIfWorkerFailed();
            if (Volatile.Read(ref disposing) != 0 || queue.IsAddingCompleted) throw new ObjectDisposedException("JsonlExperimentLogger");
        }

        private void ThrowIfWorkerFailed()
        {
            Exception error = workerError;
            if (error != null) throw new InvalidOperationException("Background JSONL writer failed.", error);
        }

        private static string BuildEnvelope(string type, string runId, long itemSequence, string payload)
        {
            return string.Concat("{\"schemaVersion\":", SchemaVersion.ToString(CultureInfo.InvariantCulture), ",\"recordType\":\"", Escape(type), "\",\"timestampUtc\":\"", DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture), "\",\"runId\":\"", Escape(runId), "\",\"sequence\":", itemSequence.ToString(CultureInfo.InvariantCulture), ",\"payload\":", payload, "}");
        }

        private static string Escape(string value)
        {
            StringBuilder result = new StringBuilder(value.Length + 8);
            foreach (char c in value)
            {
                switch (c)
                {
                    case '\"': result.Append("\\\""); break;
                    case '\\': result.Append("\\\\"); break;
                    case '\n': result.Append("\\n"); break;
                    case '\r': result.Append("\\r"); break;
                    case '\t': result.Append("\\t"); break;
                    default:
                        if (c < 0x20) result.Append("\\u").Append(((int)c).ToString("x4", CultureInfo.InvariantCulture));
                        else result.Append(c);
                        break;
                }
            }
            return result.ToString();
        }
    }

    [Serializable]
    public sealed class ExperimentRunRecord
    {
        public string scenarioId;
        public string algorithmId;
        public int randomSeed;
        public int agentCount;
        public int gridWidth;
        public int gridHeight;
        public double initializationMilliseconds;
        public double repairP95Milliseconds;
        public double cumulativePlanningCpuMilliseconds;
        public long processedNodesOrCells;
        public double frameP95Milliseconds;
        public double frameP99Milliseconds;
        public double budgetOverrunRate;
        public double successRate;
        public double arrivalTimeP95Seconds;
        public long peakManagedMemoryBytes;
        public long totalGcAllocatedBytes;
        public double meanPathEfficiency;
        public int failureCount;
    }

    [Serializable]
    public sealed class PlannerOperationRecord
    {
        public string algorithmId;
        public string operation;
        public int agentId = -1;
        public long gridVersion;
        public double elapsedCpuMilliseconds;
        public long processedNodesOrCells;
        public long expandedNodes;
        public long relaxedEdges;
        public long repairedCells;
        public long managedAllocatedBytes;
        public double budgetMilliseconds;
        public bool budgetExceeded;
        public bool succeeded;
        public string failureCode;
    }

    [Serializable]
    public sealed class FrameTimingRecord
    {
        public long frameIndex;
        public double frameTimeMilliseconds;
        public long gcAllocatedBytes;
        public long managedMemoryBytes;
    }
}
