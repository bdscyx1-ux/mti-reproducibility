using System;

namespace DDM.Research.Gate14ReME.V2
{
    /// <summary>
    /// D3 v2 captures current managed-heap occupancy. It deliberately does not
    /// claim cumulative allocation throughput. Signed deltas are preserved.
    /// </summary>
    public static class Gate14ReMEManagedHeapOccupancyV1
    {
        public const string CounterId = "GC.GetTotalMemory(false)-managed-heap-occupancy-v1";

        public static long Capture()
        {
            long value = GC.GetTotalMemory(false);
            if (value < 0L)
            {
                throw new InvalidOperationException("Managed-heap occupancy returned a negative value.");
            }
            return value;
        }

        public static long SignedDelta(long startBytes, long endBytes)
        {
            if (startBytes < 0L || endBytes < 0L)
            {
                throw new ArgumentOutOfRangeException("Managed-heap occupancy inputs must be nonnegative.");
            }
            return checked(endBytes - startBytes);
        }
    }
}
