using System.Runtime.InteropServices;

namespace DDM.Research.Gate14ReME.V3
{
    public static class Gate14ReMECumulativeAllocationCounterV1
    {
        private const string NativeLibrary = "Gate14ReMED3AllocationCounterV3";

        public struct Snapshot
        {
            public long ManagedAllocationBytes;
            public long ManagedAllocationEventCount;
            public long ForeignThreadAllocationBytes;
            public long ForeignThreadAllocationEventCount;
            public long InvalidMetadataEventCount;
            public long CounterOverflowCount;
            public uint OwnerNativeThreadId;
        }

        [DllImport(NativeLibrary, CallingConvention = CallingConvention.StdCall, ExactSpelling = true)]
        private static extern int Gate14ReMED3V3_IsReady();

        [DllImport(NativeLibrary, CallingConvention = CallingConvention.StdCall, ExactSpelling = true)]
        private static extern int Gate14ReMED3V3_GetMarkerSeen();

        [DllImport(NativeLibrary, CallingConvention = CallingConvention.StdCall, ExactSpelling = true)]
        private static extern int Gate14ReMED3V3_GetCreateCallbackRegistrationCode();

        [DllImport(NativeLibrary, CallingConvention = CallingConvention.StdCall, ExactSpelling = true)]
        private static extern int Gate14ReMED3V3_GetMarkerCallbackRegistrationCode();

        [DllImport(NativeLibrary, CallingConvention = CallingConvention.StdCall, ExactSpelling = true)]
        private static extern uint Gate14ReMED3V3_GetCurrentNativeThreadId();

        [DllImport(NativeLibrary, CallingConvention = CallingConvention.StdCall, ExactSpelling = true)]
        private static extern int Gate14ReMED3V3_BeginWindow();

        [DllImport(NativeLibrary, CallingConvention = CallingConvention.StdCall, ExactSpelling = true)]
        private static extern int Gate14ReMED3V3_SnapshotWindow(
            out long ownerBytes,
            out long ownerEvents,
            out long foreignBytes,
            out long foreignEvents,
            out long invalidMetadataEvents,
            out long overflowEvents,
            out uint ownerThreadId);

        [DllImport(NativeLibrary, CallingConvention = CallingConvention.StdCall, ExactSpelling = true)]
        private static extern int Gate14ReMED3V3_EndWindow(
            out long ownerBytes,
            out long ownerEvents,
            out long foreignBytes,
            out long foreignEvents,
            out long invalidMetadataEvents,
            out long overflowEvents,
            out uint ownerThreadId);

        public static bool IsReady() { return Gate14ReMED3V3_IsReady() == 1; }
        public static bool MarkerSeen() { return Gate14ReMED3V3_GetMarkerSeen() == 1; }
        public static int CreateCallbackRegistrationCode() { return Gate14ReMED3V3_GetCreateCallbackRegistrationCode(); }
        public static int MarkerCallbackRegistrationCode() { return Gate14ReMED3V3_GetMarkerCallbackRegistrationCode(); }
        public static uint CurrentNativeThreadId() { return Gate14ReMED3V3_GetCurrentNativeThreadId(); }
        public static int BeginWindow() { return Gate14ReMED3V3_BeginWindow(); }

        public static int SnapshotWindow(out Snapshot snapshot)
        {
            long ownerBytes;
            long ownerEvents;
            long foreignBytes;
            long foreignEvents;
            long invalidMetadataEvents;
            long overflowEvents;
            uint ownerThreadId;
            int code = Gate14ReMED3V3_SnapshotWindow(
                out ownerBytes,
                out ownerEvents,
                out foreignBytes,
                out foreignEvents,
                out invalidMetadataEvents,
                out overflowEvents,
                out ownerThreadId);
            snapshot = CreateSnapshot(ownerBytes, ownerEvents, foreignBytes, foreignEvents,
                invalidMetadataEvents, overflowEvents, ownerThreadId);
            return code;
        }

        public static int EndWindow(out Snapshot snapshot)
        {
            long ownerBytes;
            long ownerEvents;
            long foreignBytes;
            long foreignEvents;
            long invalidMetadataEvents;
            long overflowEvents;
            uint ownerThreadId;
            int code = Gate14ReMED3V3_EndWindow(
                out ownerBytes,
                out ownerEvents,
                out foreignBytes,
                out foreignEvents,
                out invalidMetadataEvents,
                out overflowEvents,
                out ownerThreadId);
            snapshot = CreateSnapshot(ownerBytes, ownerEvents, foreignBytes, foreignEvents,
                invalidMetadataEvents, overflowEvents, ownerThreadId);
            return code;
        }

        private static Snapshot CreateSnapshot(
            long ownerBytes,
            long ownerEvents,
            long foreignBytes,
            long foreignEvents,
            long invalidMetadataEvents,
            long overflowEvents,
            uint ownerThreadId)
        {
            Snapshot value = new Snapshot();
            value.ManagedAllocationBytes = ownerBytes;
            value.ManagedAllocationEventCount = ownerEvents;
            value.ForeignThreadAllocationBytes = foreignBytes;
            value.ForeignThreadAllocationEventCount = foreignEvents;
            value.InvalidMetadataEventCount = invalidMetadataEvents;
            value.CounterOverflowCount = overflowEvents;
            value.OwnerNativeThreadId = ownerThreadId;
            return value;
        }
    }
}
