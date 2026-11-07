using System.Runtime.InteropServices;

namespace DDM.Research.Gate14ReME.V3
{
    public static class Gate14ReMED3AllocationMetadataProbeV1
    {
        private const string NativeLibrary = "Gate14ReMED3AllocationMetadataProbeV1";

        public struct Snapshot
        {
            public ulong OwnerObservationCount;
            public ulong ForeignObservationCount;
            public int LastEventType;
            public uint LastEventDataCount;
            public uint LastMetadataType;
            public uint LastMetadataSize;
            public bool LastPointerNonNull;
            public bool LastRawInt64Available;
            public long LastRawInt64;
            public uint OwnerThreadId;
        }

        [DllImport(NativeLibrary, CallingConvention = CallingConvention.StdCall, ExactSpelling = true)]
        private static extern int Gate14ReMED3V3Probe_IsReady();
        [DllImport(NativeLibrary, CallingConvention = CallingConvention.StdCall, ExactSpelling = true)]
        private static extern int Gate14ReMED3V3Probe_GetMarkerSeen();
        [DllImport(NativeLibrary, CallingConvention = CallingConvention.StdCall, ExactSpelling = true)]
        private static extern int Gate14ReMED3V3Probe_GetCreateCallbackRegistrationCode();
        [DllImport(NativeLibrary, CallingConvention = CallingConvention.StdCall, ExactSpelling = true)]
        private static extern int Gate14ReMED3V3Probe_GetMarkerCallbackRegistrationCode();
        [DllImport(NativeLibrary, CallingConvention = CallingConvention.StdCall, ExactSpelling = true)]
        private static extern int Gate14ReMED3V3Probe_Begin();
        [DllImport(NativeLibrary, CallingConvention = CallingConvention.StdCall, ExactSpelling = true)]
        private static extern int Gate14ReMED3V3Probe_End(
            out ulong ownerObservationCount,
            out ulong foreignObservationCount,
            out int lastEventType,
            out uint lastEventDataCount,
            out uint lastMetadataType,
            out uint lastMetadataSize,
            out int lastPointerNonNull,
            out int lastRawInt64Available,
            out long lastRawInt64,
            out uint ownerThreadId);

        public static bool IsReady() { return Gate14ReMED3V3Probe_IsReady() == 1; }
        public static bool MarkerSeen() { return Gate14ReMED3V3Probe_GetMarkerSeen() == 1; }
        public static int CreateCallbackRegistrationCode() { return Gate14ReMED3V3Probe_GetCreateCallbackRegistrationCode(); }
        public static int MarkerCallbackRegistrationCode() { return Gate14ReMED3V3Probe_GetMarkerCallbackRegistrationCode(); }
        public static int Begin() { return Gate14ReMED3V3Probe_Begin(); }

        public static int End(out Snapshot snapshot)
        {
            ulong ownerObservationCount;
            ulong foreignObservationCount;
            int lastEventType;
            uint lastEventDataCount;
            uint lastMetadataType;
            uint lastMetadataSize;
            int lastPointerNonNull;
            int lastRawInt64Available;
            long lastRawInt64;
            uint ownerThreadId;
            int code = Gate14ReMED3V3Probe_End(
                out ownerObservationCount,
                out foreignObservationCount,
                out lastEventType,
                out lastEventDataCount,
                out lastMetadataType,
                out lastMetadataSize,
                out lastPointerNonNull,
                out lastRawInt64Available,
                out lastRawInt64,
                out ownerThreadId);
            snapshot = new Snapshot
            {
                OwnerObservationCount = ownerObservationCount,
                ForeignObservationCount = foreignObservationCount,
                LastEventType = lastEventType,
                LastEventDataCount = lastEventDataCount,
                LastMetadataType = lastMetadataType,
                LastMetadataSize = lastMetadataSize,
                LastPointerNonNull = lastPointerNonNull != 0,
                LastRawInt64Available = lastRawInt64Available != 0,
                LastRawInt64 = lastRawInt64,
                OwnerThreadId = ownerThreadId
            };
            return code;
        }
    }
}
