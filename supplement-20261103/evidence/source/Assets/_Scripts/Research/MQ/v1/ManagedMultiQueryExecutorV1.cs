using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Threading;

namespace DDM.Research.MQ.V1
{
    public sealed class ManagedMultiQueryWorkItemV1<T>
    {
        public int Ordinal { get; private set; }
        public string LaneId { get; private set; }
        public Func<T> Work { get; private set; }

        public ManagedMultiQueryWorkItemV1(int ordinal, string laneId, Func<T> work)
        {
            if (ordinal < 0) throw new ArgumentOutOfRangeException("ordinal");
            if (string.IsNullOrWhiteSpace(laneId)) throw new ArgumentException("Lane id is required.", "laneId");
            Ordinal = ordinal;
            LaneId = laneId;
            Work = work ?? throw new ArgumentNullException("work");
        }
    }

    [Serializable]
    public sealed class MultiQueryWorkerObservationV1
    {
        public int workerIndex;
        public string planId;
        public int configuredCpuSetId;
        public int configuredGroup;
        public int configuredLogicalProcessorIndex;
        public int observedGroupAfterBinding;
        public int observedLogicalProcessorAfterBinding;
        public bool exactBindingObserved;
        public string setupError;
    }

    [Serializable]
    public sealed class MultiQueryLaneRuntimeV1
    {
        public int ordinal;
        public string laneId;
        public int workerIndex;
        public string state;
        public string startedAtUtc;
        public string completedAtUtc;
        public double batchRelativeStartMilliseconds;
        public double batchRelativeEndMilliseconds;
        public double wallMilliseconds;
        public double workerThreadCpuMilliseconds;
        public long workerThreadManagedAllocatedBytes;
        public int observedGroupAtStart;
        public int observedLogicalProcessorAtStart;
        public int observedGroupAtEnd;
        public int observedLogicalProcessorAtEnd;
        public bool stayedOnConfiguredCpuSet;
        public string resultFingerprintSha256;
        public string error;
    }

    [Serializable]
    public sealed class MultiQueryBatchRuntimeV1
    {
        public string schema;
        public string batchId;
        public string executorMode;
        public string affinityPlanId;
        public string topologyRole;
        public int workerCount;
        public int laneCount;
        public string startedAtUtc;
        public string completedAtUtc;
        public double workerPoolSetupMilliseconds;
        public double batchWallMilliseconds;
        public double processCpuMilliseconds;
        public int completedLaneCount;
        public int failedLaneCount;
        public int skippedLaneCount;
        public bool succeeded;
        public string status;
        public string firstFailure;
        public MultiQueryWorkerObservationV1[] workers = new MultiQueryWorkerObservationV1[0];
        public MultiQueryLaneRuntimeV1[] lanes = new MultiQueryLaneRuntimeV1[0];
    }

    public sealed class MultiQueryBatchExecutionV1<T>
    {
        public MultiQueryBatchRuntimeV1 Runtime { get; private set; }
        public T[] Values { get; private set; }

        internal MultiQueryBatchExecutionV1(MultiQueryBatchRuntimeV1 runtime, T[] values)
        {
            Runtime = runtime ?? throw new ArgumentNullException("runtime");
            Values = values ?? throw new ArgumentNullException("values");
        }

        public void RequireSuccess()
        {
            if (!Runtime.succeeded)
            {
                throw new InvalidOperationException("Managed MQ batch failed closed: " + Runtime.firstFailure);
            }
        }
    }

    /// <summary>
    /// Deterministic fixed-worker managed MQ executor. Lane ordinal i is assigned
    /// to worker i mod W; results are always restored in ordinal order. A failed
    /// lane stops admission of all not-yet-started lanes, and the complete batch
    /// is ineligible rather than partially accepted.
    /// </summary>
    public static class ManagedMultiQueryExecutorV1
    {
        public static MultiQueryBatchExecutionV1<T> Execute<T>(
            string batchId,
            ManagedMultiQueryWorkItemV1<T>[] workItems,
            CpuAffinityPlanV1 affinityPlan,
            Func<T, string> fingerprint)
        {
            ValidateInputs(batchId, workItems, affinityPlan);

            int laneCount = workItems.Length;
            int workerCount = affinityPlan.workerCount;
            T[] values = new T[laneCount];
            MultiQueryLaneRuntimeV1[] laneRuntime = new MultiQueryLaneRuntimeV1[laneCount];
            MultiQueryWorkerObservationV1[] workerRuntime = new MultiQueryWorkerObservationV1[workerCount];
            string[] setupErrors = new string[workerCount];
            Thread[] threads = new Thread[workerCount];
            int failureFlag = 0;
            string firstFailure = string.Empty;
            object failureLock = new object();

            using (ManualResetEventSlim start = new ManualResetEventSlim(false))
            using (CountdownEvent ready = new CountdownEvent(workerCount))
            using (CountdownEvent done = new CountdownEvent(workerCount))
            {
                Stopwatch setupStopwatch = Stopwatch.StartNew();
                Stopwatch batchStopwatch = new Stopwatch();

                for (int workerIndex = 0; workerIndex < workerCount; workerIndex++)
                {
                    int capturedWorkerIndex = workerIndex;
                    threads[workerIndex] = new Thread(delegate()
                    {
                        CpuWorkerBindingV1 binding = affinityPlan.workers[capturedWorkerIndex];
                        CurrentProcessorObservationV1 setupProcessor = null;
                        try
                        {
                            WindowsCpuTopologyV1.BindCurrentThread(binding);
                            setupProcessor = WindowsCpuTopologyV1.CaptureCurrentProcessor();
                            if (setupProcessor.group != binding.group || setupProcessor.logicalProcessorIndex != binding.logicalProcessorIndex)
                            {
                                throw new InvalidOperationException("Worker did not remain on its configured CPU set during setup.");
                            }
                        }
                        catch (Exception exception)
                        {
                            setupErrors[capturedWorkerIndex] = FormatException(exception);
                            Interlocked.Exchange(ref failureFlag, 1);
                            SetFirstFailure(ref firstFailure, failureLock, setupErrors[capturedWorkerIndex]);
                        }
                        finally
                        {
                            workerRuntime[capturedWorkerIndex] = new MultiQueryWorkerObservationV1
                            {
                                workerIndex = capturedWorkerIndex,
                                planId = binding.planId,
                                configuredCpuSetId = binding.cpuSetId,
                                configuredGroup = binding.group,
                                configuredLogicalProcessorIndex = binding.logicalProcessorIndex,
                                observedGroupAfterBinding = setupProcessor == null ? -1 : setupProcessor.group,
                                observedLogicalProcessorAfterBinding = setupProcessor == null ? -1 : setupProcessor.logicalProcessorIndex,
                                exactBindingObserved = setupProcessor != null && setupProcessor.group == binding.group && setupProcessor.logicalProcessorIndex == binding.logicalProcessorIndex,
                                setupError = setupErrors[capturedWorkerIndex] ?? string.Empty
                            };
                            ready.Signal();
                        }

                        start.Wait();
                        try
                        {
                            for (int ordinal = capturedWorkerIndex; ordinal < laneCount; ordinal += workerCount)
                            {
                                ManagedMultiQueryWorkItemV1<T> item = workItems[ordinal];
                                if (!string.IsNullOrEmpty(setupErrors[capturedWorkerIndex]))
                                {
                                    laneRuntime[ordinal] = NewUnstartedRuntime(item, capturedWorkerIndex, "FAILED_WORKER_SETUP", setupErrors[capturedWorkerIndex]);
                                    continue;
                                }
                                if (Volatile.Read(ref failureFlag) != 0)
                                {
                                    laneRuntime[ordinal] = NewUnstartedRuntime(item, capturedWorkerIndex, "SKIPPED_AFTER_BATCH_FAILURE", "A prior lane or worker failed; no replacement or retry was attempted.");
                                    continue;
                                }

                                MultiQueryLaneRuntimeV1 runtime = new MultiQueryLaneRuntimeV1
                                {
                                    ordinal = ordinal,
                                    laneId = item.LaneId,
                                    workerIndex = capturedWorkerIndex,
                                    state = "RUNNING",
                                    startedAtUtc = DateTimeOffset.UtcNow.ToString("o"),
                                    batchRelativeStartMilliseconds = batchStopwatch.Elapsed.TotalMilliseconds,
                                    resultFingerprintSha256 = string.Empty,
                                    error = string.Empty
                                };
                                CurrentProcessorObservationV1 processorStart = null;
                                long cpuBefore = 0L;
                                long allocatedBefore = 0L;
                                Stopwatch laneStopwatch = Stopwatch.StartNew();
                                try
                                {
                                    processorStart = WindowsCpuTopologyV1.CaptureCurrentProcessor();
                                    cpuBefore = WindowsCpuTopologyV1.CaptureCurrentThreadCpuTime100Nanoseconds();
                                    allocatedBefore = GC.GetAllocatedBytesForCurrentThread();
                                    T value = item.Work();
                                    values[ordinal] = value;
                                    runtime.resultFingerprintSha256 = fingerprint == null ? string.Empty : (fingerprint(value) ?? string.Empty);
                                    runtime.state = "COMPLETED";
                                }
                                catch (Exception exception)
                                {
                                    runtime.state = "FAILED";
                                    runtime.error = FormatException(exception);
                                    Interlocked.Exchange(ref failureFlag, 1);
                                    SetFirstFailure(ref firstFailure, failureLock, "lane " + ordinal + " " + item.LaneId + ": " + runtime.error);
                                }
                                finally
                                {
                                    laneStopwatch.Stop();
                                    CurrentProcessorObservationV1 processorEnd = SafeCaptureProcessor();
                                    long cpuAfter = SafeCaptureThreadCpuTime(cpuBefore);
                                    long allocatedAfter = GC.GetAllocatedBytesForCurrentThread();
                                    runtime.completedAtUtc = DateTimeOffset.UtcNow.ToString("o");
                                    runtime.batchRelativeEndMilliseconds = batchStopwatch.Elapsed.TotalMilliseconds;
                                    runtime.wallMilliseconds = laneStopwatch.Elapsed.TotalMilliseconds;
                                    runtime.workerThreadCpuMilliseconds = Math.Max(0d, (cpuAfter - cpuBefore) / 10000d);
                                    runtime.workerThreadManagedAllocatedBytes = Math.Max(0L, allocatedAfter - allocatedBefore);
                                    runtime.observedGroupAtStart = processorStart == null ? -1 : processorStart.group;
                                    runtime.observedLogicalProcessorAtStart = processorStart == null ? -1 : processorStart.logicalProcessorIndex;
                                    runtime.observedGroupAtEnd = processorEnd == null ? -1 : processorEnd.group;
                                    runtime.observedLogicalProcessorAtEnd = processorEnd == null ? -1 : processorEnd.logicalProcessorIndex;
                                    runtime.stayedOnConfiguredCpuSet = processorStart != null && processorEnd != null &&
                                        processorStart.group == binding.group && processorStart.logicalProcessorIndex == binding.logicalProcessorIndex &&
                                        processorEnd.group == binding.group && processorEnd.logicalProcessorIndex == binding.logicalProcessorIndex;
                                    if (!runtime.stayedOnConfiguredCpuSet && runtime.state == "COMPLETED")
                                    {
                                        runtime.state = "FAILED";
                                        runtime.error = "Worker execution was observed outside its configured CPU set.";
                                        Interlocked.Exchange(ref failureFlag, 1);
                                        SetFirstFailure(ref firstFailure, failureLock, "lane " + ordinal + " " + item.LaneId + ": " + runtime.error);
                                    }
                                    laneRuntime[ordinal] = runtime;
                                }
                            }
                        }
                        finally
                        {
                            try { WindowsCpuTopologyV1.ClearCurrentThreadBinding(); }
                            catch (Exception exception)
                            {
                                Interlocked.Exchange(ref failureFlag, 1);
                                SetFirstFailure(ref firstFailure, failureLock, "worker " + capturedWorkerIndex + " affinity clear: " + FormatException(exception));
                            }
                            done.Signal();
                        }
                    });
                    threads[workerIndex].IsBackground = true;
                    threads[workerIndex].Name = "Gate14Re-MQ-v1-worker-" + workerIndex;
                    threads[workerIndex].Start();
                }

                ready.Wait();
                setupStopwatch.Stop();
                DateTimeOffset startedAt = DateTimeOffset.UtcNow;
                using (Process process = Process.GetCurrentProcess())
                {
                    TimeSpan processCpuBefore = process.TotalProcessorTime;
                    batchStopwatch.Start();
                    start.Set();
                    done.Wait();
                    batchStopwatch.Stop();
                    process.Refresh();
                    TimeSpan processCpuAfter = process.TotalProcessorTime;

                    for (int index = 0; index < threads.Length; index++) threads[index].Join();
                    MultiQueryBatchRuntimeV1 runtime = BuildRuntime(
                        batchId,
                        "MANAGED_FIXED_WORKER_POOL",
                        affinityPlan,
                        workItems,
                        laneRuntime,
                        workerRuntime,
                        startedAt,
                        setupStopwatch.Elapsed.TotalMilliseconds,
                        batchStopwatch.Elapsed.TotalMilliseconds,
                        Math.Max(0d, (processCpuAfter - processCpuBefore).TotalMilliseconds),
                        firstFailure);
                    return new MultiQueryBatchExecutionV1<T>(runtime, values);
                }
            }
        }

        internal static void ValidateInputs<T>(
            string batchId,
            ManagedMultiQueryWorkItemV1<T>[] workItems,
            CpuAffinityPlanV1 affinityPlan)
        {
            if (string.IsNullOrWhiteSpace(batchId)) throw new ArgumentException("Batch id is required.", "batchId");
            if (workItems == null || workItems.Length == 0) throw new ArgumentException("At least one work item is required.", "workItems");
            if (affinityPlan == null) throw new ArgumentNullException("affinityPlan");
            if (affinityPlan.workers == null || affinityPlan.workers.Length != affinityPlan.workerCount || affinityPlan.workerCount <= 0)
                throw new ArgumentException("Affinity plan worker cardinality is invalid.", "affinityPlan");
            if (affinityPlan.workerCount > workItems.Length) throw new ArgumentException("Worker count cannot exceed lane count.", "affinityPlan");

            HashSet<string> laneIds = new HashSet<string>(StringComparer.Ordinal);
            for (int index = 0; index < workItems.Length; index++)
            {
                ManagedMultiQueryWorkItemV1<T> item = workItems[index];
                if (item == null) throw new ArgumentException("Work item " + index + " is null.", "workItems");
                if (item.Ordinal != index) throw new ArgumentException("Work-item ordinals must be exactly contiguous 0..N-1.", "workItems");
                if (!laneIds.Add(item.LaneId)) throw new ArgumentException("Work-item lane ids must be unique.", "workItems");
            }
            for (int index = 0; index < affinityPlan.workers.Length; index++)
            {
                CpuWorkerBindingV1 binding = affinityPlan.workers[index];
                if (binding == null || binding.workerIndex != index) throw new ArgumentException("Affinity worker indices must be exactly contiguous 0..W-1.", "affinityPlan");
            }
        }

        internal static MultiQueryBatchRuntimeV1 BuildRuntime<T>(
            string batchId,
            string executorMode,
            CpuAffinityPlanV1 affinityPlan,
            ManagedMultiQueryWorkItemV1<T>[] workItems,
            MultiQueryLaneRuntimeV1[] laneRuntime,
            MultiQueryWorkerObservationV1[] workerRuntime,
            DateTimeOffset startedAt,
            double setupMilliseconds,
            double batchWallMilliseconds,
            double processCpuMilliseconds,
            string firstFailure)
        {
            int completed = 0;
            int failed = 0;
            int skipped = 0;
            for (int index = 0; index < laneRuntime.Length; index++)
            {
                if (laneRuntime[index] == null)
                {
                    laneRuntime[index] = NewUnstartedRuntime(workItems[index], -1, "FAILED_MISSING_RUNTIME", "Executor did not emit a lane terminal state.");
                }
                if (laneRuntime[index].state == "COMPLETED") completed++;
                else if (laneRuntime[index].state.StartsWith("SKIPPED", StringComparison.Ordinal)) skipped++;
                else failed++;
            }
            bool succeeded = completed == laneRuntime.Length && failed == 0 && skipped == 0;
            return new MultiQueryBatchRuntimeV1
            {
                schema = "gate14re-mq-managed-batch-runtime-v1",
                batchId = batchId,
                executorMode = executorMode,
                affinityPlanId = affinityPlan.planId,
                topologyRole = affinityPlan.topologyRole,
                workerCount = affinityPlan.workerCount,
                laneCount = laneRuntime.Length,
                startedAtUtc = startedAt.ToString("o"),
                completedAtUtc = DateTimeOffset.UtcNow.ToString("o"),
                workerPoolSetupMilliseconds = setupMilliseconds,
                batchWallMilliseconds = batchWallMilliseconds,
                processCpuMilliseconds = processCpuMilliseconds,
                completedLaneCount = completed,
                failedLaneCount = failed,
                skippedLaneCount = skipped,
                succeeded = succeeded,
                status = succeeded ? "PASS_ALL_LANES_COMPLETED" : "FAIL_CLOSED_BATCH_INELIGIBLE",
                firstFailure = succeeded ? string.Empty : (string.IsNullOrEmpty(firstFailure) ? "One or more lanes did not complete." : firstFailure),
                workers = workerRuntime,
                lanes = laneRuntime
            };
        }

        internal static MultiQueryLaneRuntimeV1 NewUnstartedRuntime<T>(
            ManagedMultiQueryWorkItemV1<T> item,
            int workerIndex,
            string state,
            string error)
        {
            return new MultiQueryLaneRuntimeV1
            {
                ordinal = item.Ordinal,
                laneId = item.LaneId,
                workerIndex = workerIndex,
                state = state,
                startedAtUtc = string.Empty,
                completedAtUtc = DateTimeOffset.UtcNow.ToString("o"),
                resultFingerprintSha256 = string.Empty,
                error = error ?? string.Empty,
                observedGroupAtStart = -1,
                observedLogicalProcessorAtStart = -1,
                observedGroupAtEnd = -1,
                observedLogicalProcessorAtEnd = -1
            };
        }

        internal static string FormatException(Exception exception)
        {
            return exception == null ? string.Empty : exception.GetType().FullName + ": " + exception.Message;
        }

        internal static void SetFirstFailure(ref string firstFailure, object sync, string message)
        {
            lock (sync)
            {
                if (string.IsNullOrEmpty(firstFailure)) firstFailure = message ?? string.Empty;
            }
        }

        private static CurrentProcessorObservationV1 SafeCaptureProcessor()
        {
            try { return WindowsCpuTopologyV1.CaptureCurrentProcessor(); }
            catch { return null; }
        }

        private static long SafeCaptureThreadCpuTime(long fallback)
        {
            try { return WindowsCpuTopologyV1.CaptureCurrentThreadCpuTime100Nanoseconds(); }
            catch { return fallback; }
        }
    }

    /// <summary>
    /// Direct serial baseline. It uses the same lane work and result fingerprinting
    /// but does not create a queue or worker pool, so ST-direct versus MQ-1 exposes
    /// executor overhead without changing the algorithm workload.
    /// </summary>
    public static class DirectMultiQueryExecutorV1
    {
        public static MultiQueryBatchExecutionV1<T> Execute<T>(
            string batchId,
            ManagedMultiQueryWorkItemV1<T>[] workItems,
            CpuAffinityPlanV1 singleCorePlan,
            Func<T, string> fingerprint)
        {
            ManagedMultiQueryExecutorV1.ValidateInputs(batchId, workItems, singleCorePlan);
            if (singleCorePlan.workerCount != 1) throw new ArgumentException("ST-direct requires exactly one affinity binding.", "singleCorePlan");

            T[] values = new T[workItems.Length];
            MultiQueryLaneRuntimeV1[] laneRuntime = new MultiQueryLaneRuntimeV1[workItems.Length];
            CpuWorkerBindingV1 binding = singleCorePlan.workers[0];
            MultiQueryWorkerObservationV1 workerObservation = null;
            string firstFailure = string.Empty;
            DateTimeOffset startedAt = DateTimeOffset.UtcNow;
            Stopwatch batchStopwatch = Stopwatch.StartNew();

            using (Process process = Process.GetCurrentProcess())
            {
                TimeSpan processCpuBefore = process.TotalProcessorTime;
                try
                {
                    WindowsCpuTopologyV1.BindCurrentThread(binding);
                    CurrentProcessorObservationV1 setup = WindowsCpuTopologyV1.CaptureCurrentProcessor();
                    workerObservation = new MultiQueryWorkerObservationV1
                    {
                        workerIndex = 0,
                        planId = binding.planId,
                        configuredCpuSetId = binding.cpuSetId,
                        configuredGroup = binding.group,
                        configuredLogicalProcessorIndex = binding.logicalProcessorIndex,
                        observedGroupAfterBinding = setup.group,
                        observedLogicalProcessorAfterBinding = setup.logicalProcessorIndex,
                        exactBindingObserved = setup.group == binding.group && setup.logicalProcessorIndex == binding.logicalProcessorIndex,
                        setupError = string.Empty
                    };

                    for (int ordinal = 0; ordinal < workItems.Length; ordinal++)
                    {
                        ManagedMultiQueryWorkItemV1<T> item = workItems[ordinal];
                        if (!string.IsNullOrEmpty(firstFailure))
                        {
                            laneRuntime[ordinal] = ManagedMultiQueryExecutorV1.NewUnstartedRuntime(item, 0, "SKIPPED_AFTER_BATCH_FAILURE", "A prior direct lane failed; no replacement or retry was attempted.");
                            continue;
                        }

                        MultiQueryLaneRuntimeV1 runtime = new MultiQueryLaneRuntimeV1
                        {
                            ordinal = ordinal,
                            laneId = item.LaneId,
                            workerIndex = 0,
                            state = "RUNNING",
                            startedAtUtc = DateTimeOffset.UtcNow.ToString("o"),
                            batchRelativeStartMilliseconds = batchStopwatch.Elapsed.TotalMilliseconds,
                            resultFingerprintSha256 = string.Empty,
                            error = string.Empty
                        };
                        CurrentProcessorObservationV1 processorStart = null;
                        long cpuBefore = 0L;
                        long allocatedBefore = 0L;
                        Stopwatch laneStopwatch = Stopwatch.StartNew();
                        try
                        {
                            processorStart = WindowsCpuTopologyV1.CaptureCurrentProcessor();
                            cpuBefore = WindowsCpuTopologyV1.CaptureCurrentThreadCpuTime100Nanoseconds();
                            allocatedBefore = GC.GetAllocatedBytesForCurrentThread();
                            T value = item.Work();
                            values[ordinal] = value;
                            runtime.resultFingerprintSha256 = fingerprint == null ? string.Empty : (fingerprint(value) ?? string.Empty);
                            runtime.state = "COMPLETED";
                        }
                        catch (Exception exception)
                        {
                            runtime.state = "FAILED";
                            runtime.error = ManagedMultiQueryExecutorV1.FormatException(exception);
                            firstFailure = "lane " + ordinal + " " + item.LaneId + ": " + runtime.error;
                        }
                        finally
                        {
                            laneStopwatch.Stop();
                            CurrentProcessorObservationV1 processorEnd = WindowsCpuTopologyV1.CaptureCurrentProcessor();
                            long cpuAfter = WindowsCpuTopologyV1.CaptureCurrentThreadCpuTime100Nanoseconds();
                            long allocatedAfter = GC.GetAllocatedBytesForCurrentThread();
                            runtime.completedAtUtc = DateTimeOffset.UtcNow.ToString("o");
                            runtime.batchRelativeEndMilliseconds = batchStopwatch.Elapsed.TotalMilliseconds;
                            runtime.wallMilliseconds = laneStopwatch.Elapsed.TotalMilliseconds;
                            runtime.workerThreadCpuMilliseconds = Math.Max(0d, (cpuAfter - cpuBefore) / 10000d);
                            runtime.workerThreadManagedAllocatedBytes = Math.Max(0L, allocatedAfter - allocatedBefore);
                            runtime.observedGroupAtStart = processorStart == null ? -1 : processorStart.group;
                            runtime.observedLogicalProcessorAtStart = processorStart == null ? -1 : processorStart.logicalProcessorIndex;
                            runtime.observedGroupAtEnd = processorEnd.group;
                            runtime.observedLogicalProcessorAtEnd = processorEnd.logicalProcessorIndex;
                            runtime.stayedOnConfiguredCpuSet = processorStart != null &&
                                processorStart.group == binding.group && processorStart.logicalProcessorIndex == binding.logicalProcessorIndex &&
                                processorEnd.group == binding.group && processorEnd.logicalProcessorIndex == binding.logicalProcessorIndex;
                            if (!runtime.stayedOnConfiguredCpuSet && runtime.state == "COMPLETED")
                            {
                                runtime.state = "FAILED";
                                runtime.error = "Direct execution was observed outside its configured CPU set.";
                                firstFailure = "lane " + ordinal + " " + item.LaneId + ": " + runtime.error;
                            }
                            laneRuntime[ordinal] = runtime;
                        }
                    }
                }
                catch (Exception exception)
                {
                    firstFailure = ManagedMultiQueryExecutorV1.FormatException(exception);
                    if (workerObservation == null)
                    {
                        workerObservation = new MultiQueryWorkerObservationV1
                        {
                            workerIndex = 0,
                            planId = binding.planId,
                            configuredCpuSetId = binding.cpuSetId,
                            configuredGroup = binding.group,
                            configuredLogicalProcessorIndex = binding.logicalProcessorIndex,
                            observedGroupAfterBinding = -1,
                            observedLogicalProcessorAfterBinding = -1,
                            exactBindingObserved = false,
                            setupError = firstFailure
                        };
                    }
                }
                finally
                {
                    try { WindowsCpuTopologyV1.ClearCurrentThreadBinding(); }
                    catch (Exception exception)
                    {
                        if (string.IsNullOrEmpty(firstFailure)) firstFailure = "affinity clear: " + ManagedMultiQueryExecutorV1.FormatException(exception);
                    }
                }

                batchStopwatch.Stop();
                process.Refresh();
                TimeSpan processCpuAfter = process.TotalProcessorTime;
                MultiQueryBatchRuntimeV1 batchRuntime = ManagedMultiQueryExecutorV1.BuildRuntime(
                    batchId,
                    "ST_DIRECT_SERIAL_CALLER_THREAD",
                    singleCorePlan,
                    workItems,
                    laneRuntime,
                    new[] { workerObservation },
                    startedAt,
                    0d,
                    batchStopwatch.Elapsed.TotalMilliseconds,
                    Math.Max(0d, (processCpuAfter - processCpuBefore).TotalMilliseconds),
                    firstFailure);
                return new MultiQueryBatchExecutionV1<T>(batchRuntime, values);
            }
        }
    }
}
