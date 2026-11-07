using System;
using System.Collections.Generic;

namespace DDM.Research.Gate14Re.V2
{
    public static class Gate14ReFormalMathV1
    {
        public static int[] ComputeAndApplyCommonM2Mask(Gate14ReMovementAlgorithmRawV1[] samples, int minimum)
        {
            if (samples == null || samples.Length != 4) throw new ArgumentException("M2 common mask requires exactly four algorithm samples.", "samples");
            if (minimum < 1) throw new ArgumentOutOfRangeException("minimum");
            if (samples[0] == null || samples[0].units == null) throw new ArgumentException("M2 sample units are missing.", "samples");

            int unitCount = samples[0].units.Length;
            List<int> mask = new List<int>();
            for (int unitIndex = 0; unitIndex < unitCount; unitIndex++)
            {
                int identity = samples[0].units[unitIndex].agentId;
                bool valid = true;
                for (int algorithm = 0; algorithm < samples.Length; algorithm++)
                {
                    if (samples[algorithm] == null || samples[algorithm].units == null || samples[algorithm].units.Length != unitCount)
                        throw new ArgumentException("M2 algorithm samples do not have the same unit cardinality.", "samples");
                    Gate14ReUnitRawV1 unit = samples[algorithm].units[unitIndex];
                    if (unit == null || unit.agentId != identity || !unit.arrived || unit.cumulativeHorizontalPathLength < 0d || double.IsNaN(unit.cumulativeHorizontalPathLength) || double.IsInfinity(unit.cumulativeHorizontalPathLength))
                    {
                        valid = false;
                        break;
                    }
                }
                if (valid) mask.Add(identity);
            }

            bool sufficient = mask.Count >= minimum;
            for (int algorithm = 0; algorithm < samples.Length; algorithm++)
            {
                Gate14ReMovementAlgorithmRawV1 sample = samples[algorithm];
                sample.m2CommonMaskCount = mask.Count;
                sample.m2CommonMaskSufficient = sufficient;
                if (!sufficient)
                {
                    sample.m2CommonMaskMeanPathLength = -1d;
                    continue;
                }
                double sum = 0d;
                int cursor = 0;
                for (int index = 0; index < sample.units.Length && cursor < mask.Count; index++)
                {
                    if (sample.units[index].agentId == mask[cursor])
                    {
                        sum += sample.units[index].cumulativeHorizontalPathLength;
                        cursor++;
                    }
                }
                if (cursor != mask.Count) throw new InvalidOperationException("M2 common-mask identity order drifted between algorithms.");
                sample.m2CommonMaskMeanPathLength = sum / mask.Count;
            }
            return mask.ToArray();
        }

        public static void SummarizeFrameIntervals(double[] raw, out double median, out double nearestRankP95)
        {
            if (raw == null || raw.Length != 1800) throw new ArgumentException("M4 requires exactly 1,800 frame intervals.", "raw");
            double[] sorted = (double[])raw.Clone();
            for (int index = 0; index < sorted.Length; index++)
            {
                if (sorted[index] <= 0d || double.IsNaN(sorted[index]) || double.IsInfinity(sorted[index]))
                    throw new ArgumentException("M4 frame intervals must be finite and positive.", "raw");
            }
            Array.Sort(sorted);
            median = (sorted[899] + sorted[900]) * 0.5d;
            int p95Index = (int)Math.Ceiling(0.95d * sorted.Length) - 1;
            nearestRankP95 = sorted[p95Index];
        }
    }
}
