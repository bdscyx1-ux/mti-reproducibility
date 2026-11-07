using System;

namespace DDM.Research.Gate14ReME.V2
{
    /// <summary>
    /// Process-wide monotonic managed-allocation counter for Gate14Re-ME D3.
    /// Native allocations are excluded. Runtime qualification is mandatory before use.
    /// </summary>
    public static class Gate14ReMEAllocationCounterV2
    {
        public const string CounterId = "GC.GetTotalAllocatedBytes(precise:true)-process-wide-v2";

        public static long Capture()
        {
            long value = GC.GetTotalAllocatedBytes(precise: true);
            if (value < 0L)
            {
                throw new InvalidOperationException("The process-wide managed-allocation counter returned a negative value.");
            }
            return value;
        }

        public static long Difference(long before, long after)
        {
            if (before < 0L || after < before)
            {
                throw new InvalidOperationException("The process-wide managed-allocation counter was non-monotonic.");
            }
            return checked(after - before);
        }
    }
}
