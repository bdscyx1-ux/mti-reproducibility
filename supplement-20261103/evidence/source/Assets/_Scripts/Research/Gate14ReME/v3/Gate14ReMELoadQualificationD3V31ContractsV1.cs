using System;
using System.Diagnostics;

namespace DDM.Research.Gate14ReME.V3
{
    public static class Gate14ReMED3V31QualificationConstantsV1
    {
        public const string CounterId = "GC.Alloc-Begin-owner-thread-window-v3.1";
        public const string SemanticVersion = "3.1";
        public const string ContractRelativePath = "Research/Gate14Re-ME/Execution/v3/d3-cumulative-managed-allocation-contract.qualified.v1.json";
        public const string ContractSha256 = "a60531b41c4a3c61e9c0cdc31828d6e34a458f5cf4ae97413538d24c07ecbdce";
        public const string D3WindowFileName = "d3-windows.raw.v1.jsonl";
        public const string EventGroupFileName = "event-groups.raw.v2.jsonl";
        public const string EmptyBoundaryFileName = "empty-boundary.raw.v2.jsonl";
        public const string LaneReceiptSchema = "gate14re-me-qualification-lane-receipt-v2";
        public const string EmptyBoundaryReceiptSchema = "gate14re-me-empty-boundary-receipt-v2";
        public const string InstrumentReceiptSchema = "gate14re-me-instrument-qualification-receipt-v2";
    }

    [Serializable]
    public sealed class Gate14ReMED3WindowRawV1
    {
        public string recordId;
        public string inputId;
        public string superblockId;
        public string anonymousLaneId;
        public string identityBindingSha256;
        public string measurementScope;
        public int eventGroupIndex;
        public int processOrdinal;
        public int iterationIndex;
        public string d3CounterId;
        public string d3SemanticVersion;
        public long managedAllocationBytes;
        public long managedAllocationEventCount;
        public long foreignThreadAllocationBytes;
        public long foreignThreadAllocationEventCount;
        public long invalidMetadataEventCount;
        public long counterOverflowCount;
        public long ownerNativeThreadId;
        public long observerNativeThreadId;
        public long windowStartStopwatchTicks;
        public long windowEndStopwatchTicks;
        public long windowElapsedStopwatchTicks;
        public long stopwatchFrequency;
        public double managedAllocationRateBytesPerSecond;
        public bool managedAllocationRateValid;
        public int beginReturnCode;
        public int endReturnCode;
        public bool pluginReady;
        public bool markerSeen;
        public bool metadataAbiValid;
        public bool ownerThreadMatched;
        public bool counterValid;
        public string invalidReasonCode;
        public string d3ContractRelativePath;
        public string d3ContractSha256;
        public string sourceRelativePath;
        public string sourceSha256;
    }

    /// <summary>
    /// Fail-closed lifetime wrapper for one native D3-v3.1 window. Construction and
    /// raw-record allocation occur outside the measured window. Dispose always asks
    /// the native plugin to close an opened window, including exceptional exits.
    /// </summary>
    public sealed class Gate14ReMED3MeasurementWindowV1 : IDisposable
    {
        private bool _closed;
        private Gate14ReMECumulativeAllocationCounterV2.Snapshot _snapshot;

        public long StartStopwatchTicks { get; private set; }
        public long EndStopwatchTicks { get; private set; }
        public int BeginReturnCode { get; private set; }
        public int EndReturnCode { get; private set; }

        public Gate14ReMED3MeasurementWindowV1()
        {
            StartStopwatchTicks = Stopwatch.GetTimestamp();
            BeginReturnCode = Gate14ReMECumulativeAllocationCounterV2.BeginWindow();
            EndReturnCode = int.MinValue;
            if (BeginReturnCode != 0)
            {
                EndStopwatchTicks = Stopwatch.GetTimestamp();
                _closed = true;
                throw new InvalidOperationException("D3-v3.1 BeginWindow failed with code " + BeginReturnCode + ".");
            }
        }

        public void Close()
        {
            if (_closed) return;
            EndReturnCode = Gate14ReMECumulativeAllocationCounterV2.EndWindow(out _snapshot);
            EndStopwatchTicks = Stopwatch.GetTimestamp();
            _closed = true;
        }

        public void Dispose()
        {
            Close();
        }

        public Gate14ReMED3WindowRawV1 CreateRawRecord(
            string recordId,
            string inputId,
            string superblockId,
            string anonymousLaneId,
            string identityBindingSha256,
            string measurementScope,
            int eventGroupIndex,
            int processOrdinal,
            int iterationIndex,
            string sourceRelativePath,
            string sourceSha256)
        {
            if (!_closed) throw new InvalidOperationException("D3-v3.1 raw record requested before EndWindow.");
            long elapsed = EndStopwatchTicks - StartStopwatchTicks;
            bool elapsedValid = elapsed > 0L && Stopwatch.Frequency > 0L;
            double rate = elapsedValid
                ? _snapshot.ManagedAllocationBytes * (double)Stopwatch.Frequency / elapsed
                : 0.0;
            bool rateFinite = !double.IsNaN(rate) && !double.IsInfinity(rate);
            bool rateValid = _snapshot.ManagedAllocationBytes > 0L && elapsedValid && rate > 0d && rateFinite;
            if (!rateFinite) rate = 0.0;

            long observerThreadId = Gate14ReMECumulativeAllocationCounterV2.CurrentNativeThreadId();
            bool pluginReady = Gate14ReMECumulativeAllocationCounterV2.IsReady();
            bool markerSeen = Gate14ReMECumulativeAllocationCounterV2.MarkerSeen();
            bool abiValid = Gate14ReMECumulativeAllocationCounterV2.CreateCallbackRegistrationCode() == 0 &&
                Gate14ReMECumulativeAllocationCounterV2.MarkerCallbackRegistrationCode() == 0 &&
                Gate14ReMECumulativeAllocationCounterV2.RequiredMetadataTypeValue() == 3 &&
                Gate14ReMECumulativeAllocationCounterV2.RequiredMetadataSizeBytes() == 4;
            bool ownerMatched = _snapshot.OwnerNativeThreadId != 0U && _snapshot.OwnerNativeThreadId == observerThreadId;
            bool nonnegative = _snapshot.ManagedAllocationBytes >= 0L &&
                _snapshot.ManagedAllocationEventCount >= 0L &&
                _snapshot.ForeignThreadAllocationBytes >= 0L &&
                _snapshot.ForeignThreadAllocationEventCount >= 0L;
            bool valid = BeginReturnCode == 0 && EndReturnCode == 0 && pluginReady && markerSeen && abiValid &&
                ownerMatched && nonnegative && _snapshot.InvalidMetadataEventCount == 0L &&
                _snapshot.CounterOverflowCount == 0L && elapsed >= 0L;

            string reason = string.Empty;
            if (BeginReturnCode != 0) reason = "D3_BEGIN_FAILED";
            else if (EndReturnCode != 0) reason = "D3_END_FAILED";
            else if (!pluginReady) reason = "D3_PLUGIN_NOT_READY";
            else if (!markerSeen) reason = "D3_GC_ALLOC_MARKER_NOT_SEEN";
            else if (!abiValid) reason = "D3_METADATA_ABI_INVALID";
            else if (!ownerMatched) reason = "D3_OWNER_THREAD_MISMATCH";
            else if (!nonnegative) reason = "D3_NEGATIVE_COUNTER";
            else if (_snapshot.InvalidMetadataEventCount != 0L) reason = "D3_INVALID_METADATA_EVENT";
            else if (_snapshot.CounterOverflowCount != 0L) reason = "D3_COUNTER_OVERFLOW";
            else if (elapsed < 0L) reason = "D3_CLOCK_REGRESSION";

            return new Gate14ReMED3WindowRawV1
            {
                recordId = recordId ?? string.Empty,
                inputId = inputId ?? string.Empty,
                superblockId = superblockId ?? string.Empty,
                anonymousLaneId = anonymousLaneId ?? string.Empty,
                identityBindingSha256 = identityBindingSha256 ?? string.Empty,
                measurementScope = measurementScope ?? string.Empty,
                eventGroupIndex = eventGroupIndex,
                processOrdinal = processOrdinal,
                iterationIndex = iterationIndex,
                d3CounterId = Gate14ReMED3V31QualificationConstantsV1.CounterId,
                d3SemanticVersion = Gate14ReMED3V31QualificationConstantsV1.SemanticVersion,
                managedAllocationBytes = _snapshot.ManagedAllocationBytes,
                managedAllocationEventCount = _snapshot.ManagedAllocationEventCount,
                foreignThreadAllocationBytes = _snapshot.ForeignThreadAllocationBytes,
                foreignThreadAllocationEventCount = _snapshot.ForeignThreadAllocationEventCount,
                invalidMetadataEventCount = _snapshot.InvalidMetadataEventCount,
                counterOverflowCount = _snapshot.CounterOverflowCount,
                ownerNativeThreadId = _snapshot.OwnerNativeThreadId,
                observerNativeThreadId = observerThreadId,
                windowStartStopwatchTicks = StartStopwatchTicks,
                windowEndStopwatchTicks = EndStopwatchTicks,
                windowElapsedStopwatchTicks = elapsed,
                stopwatchFrequency = Stopwatch.Frequency,
                managedAllocationRateBytesPerSecond = rate,
                managedAllocationRateValid = rateValid,
                beginReturnCode = BeginReturnCode,
                endReturnCode = EndReturnCode,
                pluginReady = pluginReady,
                markerSeen = markerSeen,
                metadataAbiValid = abiValid,
                ownerThreadMatched = ownerMatched,
                counterValid = valid,
                invalidReasonCode = reason,
                d3ContractRelativePath = Gate14ReMED3V31QualificationConstantsV1.ContractRelativePath,
                d3ContractSha256 = Gate14ReMED3V31QualificationConstantsV1.ContractSha256,
                sourceRelativePath = sourceRelativePath ?? string.Empty,
                sourceSha256 = sourceSha256 ?? string.Empty
            };
        }
    }

    [Serializable]
    public sealed class Gate14ReMEEventGroupRawV2
    {
        public string recordId;
        public string inputId;
        public string superblockId;
        public string designRegion;
        public string anonymousLaneId;
        public string identityBindingSha256;
        public int gridEdge;
        public int agentCount;
        public int changedCellCount;
        public string changeTopology;
        public string graphProfile;
        public int sameTickAtomicPartitions;
        public string contextStratumId;
        public string eventGroupId;
        public int eventGroupIndex;
        public int cycleIndex;
        public string phase;
        public double eventGroupElapsedMilliseconds;
        public string d3WindowRecordId;
        public string d3CounterId;
        public bool d3CounterValid;
        public long gridContainsCalls;
        public long gridIsWalkableCalls;
        public long gridGetTraversalCostCalls;
        public long gridAccessorCallsTotal;
        public int repairOperationCount;
        public int planOperationCount;
        public int succeededPlanCount;
        public int noPathPlanCount;
        public int budgetExceededOperationCount;
        public bool eligible;
        public string missingOrIneligibleReasonCode;
        public bool finitePositiveElapsed;
        public bool counterValid;
        public string sourceRelativePath;
        public string sourceSha256;
    }

    [Serializable]
    public sealed class Gate14ReMEEmptyBoundaryRawV2
    {
        public string recordId;
        public int processOrdinal;
        public int iterationIndex;
        public long stopwatchStartTicks;
        public long stopwatchEndTicks;
        public double elapsedMilliseconds;
        public string d3WindowRecordId;
        public string d3CounterId;
        public bool d3CounterValid;
        public bool plannerInvoked;
        public string sourceRelativePath;
        public string sourceSha256;
    }

    [Serializable]
    public sealed class Gate14ReMELaneReceiptV2
    {
        public string schema;
        public string studyId;
        public string protocolId;
        public string status;
        public string inputId;
        public string superblockId;
        public string anonymousLaneId;
        public string identityBindingSha256;
        public string inputRelativePath;
        public string inputSha256;
        public string oracleReceiptRelativePath;
        public string oracleReceiptSha256;
        public string implementationManifestSha256;
        public string fairnessBindingSha256;
        public string resourceBudgetSha256;
        public string d3ContractSha256;
        public int eventGroupRows;
        public int operationRows;
        public int d3WindowRows;
        public int persistentStateRows;
        public int processResourceRows;
        public long peakCommittedBytes;
        public double laneWallClockMilliseconds;
        public bool instrumentValid;
        public bool completed;
        public string failureReasonCode;
        public string createdAtUtc;
    }

    [Serializable]
    public sealed class Gate14ReMEEmptyBoundaryReceiptV2
    {
        public string schema;
        public string studyId;
        public string status;
        public int processOrdinal;
        public int rawIterationRows;
        public int d3WindowRows;
        public bool plannerInvoked;
        public string d3ContractSha256;
        public string implementationManifestSha256;
        public string resourceBudgetSha256;
        public string createdAtUtc;
    }

    [Serializable]
    public sealed class Gate14ReMEInstrumentQualificationReceiptV2
    {
        public string schema;
        public string studyId;
        public string status;
        public bool gridReadProxyKnownAnswerPassed;
        public bool gridReadProxySemanticInvariancePassed;
        public bool d3V31PluginReadinessPassed;
        public bool d3V31OneMiBPositiveControlPassed;
        public bool d3V31RateFormulaPassed;
        public bool persistentStateSizerSyntheticFixturePassed;
        public bool clockMonotonicityPassed;
        public bool rawToExportRoundTripPassed;
        public bool tamperNegativeTestPassed;
        public bool missingNegativeTestPassed;
        public bool duplicateNegativeTestPassed;
        public bool anonymousLabelSwapNegativeTestPassed;
        public string d3ContractSha256;
        public string implementationManifestSha256;
        public string createdAtUtc;
    }
}
