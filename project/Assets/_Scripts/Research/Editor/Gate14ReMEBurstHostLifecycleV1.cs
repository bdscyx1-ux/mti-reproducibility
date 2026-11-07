using System;
using System.Diagnostics;
using System.Reflection;
using System.Threading;

namespace DDM.Research.Editor
{
    /// <summary>
    /// Structural Unity-host guard used only after a runner has frozen its
    /// result. It waits for Burst's own current-compilation predicate before
    /// allowing the editor domain to unload.
    /// </summary>
    internal static class Gate14ReMEBurstHostLifecycleV1
    {
        internal sealed class WaitResult
        {
            public bool initialCompilationDone;
            public bool finalCompilationDone;
            public int requiredConsecutiveDoneObservations;
            public int achievedConsecutiveDoneObservations;
            public int pollCount;
            public long elapsedMilliseconds;
            public string reflectedType;
            public string reflectedMethod;
        }

        internal static WaitResult WaitForCurrentCompilationDone(
            int timeoutMilliseconds,
            int pollMilliseconds = 100,
            int requiredConsecutiveDoneObservations = 3)
        {
            if (timeoutMilliseconds <= 0 || timeoutMilliseconds > 300000)
            {
                throw new ArgumentOutOfRangeException(nameof(timeoutMilliseconds));
            }
            if (pollMilliseconds <= 0 || pollMilliseconds > timeoutMilliseconds)
            {
                throw new ArgumentOutOfRangeException(nameof(pollMilliseconds));
            }
            if (requiredConsecutiveDoneObservations <= 0 || requiredConsecutiveDoneObservations > 20)
            {
                throw new ArgumentOutOfRangeException(nameof(requiredConsecutiveDoneObservations));
            }

            Type burstCompilerType = ResolveBurstCompilerType();
            MethodInfo isCurrentCompilationDone = burstCompilerType.GetMethod(
                "IsCurrentCompilationDone",
                BindingFlags.Static | BindingFlags.NonPublic);
            if (isCurrentCompilationDone == null || isCurrentCompilationDone.ReturnType != typeof(bool))
            {
                throw new MissingMethodException(burstCompilerType.FullName, "IsCurrentCompilationDone");
            }

            Stopwatch stopwatch = Stopwatch.StartNew();
            int pollCount = 0;
            int consecutiveDone = 0;
            bool initialDone = InvokeCompilationDone(isCurrentCompilationDone);
            pollCount++;
            if (initialDone) consecutiveDone = 1;

            while (consecutiveDone < requiredConsecutiveDoneObservations)
            {
                if (stopwatch.ElapsedMilliseconds >= timeoutMilliseconds)
                {
                    throw new TimeoutException(
                        "Burst current compilation did not reach the required stable completed state within "
                        + timeoutMilliseconds + " milliseconds.");
                }

                int remaining = timeoutMilliseconds - (int)Math.Min(timeoutMilliseconds, stopwatch.ElapsedMilliseconds);
                Thread.Sleep(Math.Min(pollMilliseconds, remaining));
                bool done = InvokeCompilationDone(isCurrentCompilationDone);
                pollCount++;
                consecutiveDone = done ? consecutiveDone + 1 : 0;
            }

            stopwatch.Stop();
            return new WaitResult
            {
                initialCompilationDone = initialDone,
                finalCompilationDone = true,
                requiredConsecutiveDoneObservations = requiredConsecutiveDoneObservations,
                achievedConsecutiveDoneObservations = consecutiveDone,
                pollCount = pollCount,
                elapsedMilliseconds = stopwatch.ElapsedMilliseconds,
                reflectedType = burstCompilerType.AssemblyQualifiedName,
                reflectedMethod = isCurrentCompilationDone.Name
            };
        }

        private static Type ResolveBurstCompilerType()
        {
            Type type = Type.GetType("Unity.Burst.BurstCompiler, Unity.Burst", false);
            if (type != null) return type;

            Assembly[] assemblies = AppDomain.CurrentDomain.GetAssemblies();
            for (int index = 0; index < assemblies.Length; index++)
            {
                type = assemblies[index].GetType("Unity.Burst.BurstCompiler", false);
                if (type != null) return type;
            }

            throw new TypeLoadException("Unity.Burst.BurstCompiler is not loaded.");
        }

        private static bool InvokeCompilationDone(MethodInfo method)
        {
            try
            {
                return (bool)method.Invoke(null, null);
            }
            catch (TargetInvocationException exception)
            {
                throw new InvalidOperationException(
                    "Burst IsCurrentCompilationDone invocation failed.",
                    exception.InnerException ?? exception);
            }
        }
    }
}
