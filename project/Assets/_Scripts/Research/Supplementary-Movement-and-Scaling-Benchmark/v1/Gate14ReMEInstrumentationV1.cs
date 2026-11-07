using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Reflection;
using DDM.Research.Navigation;

namespace DDM.Research.Gate14ReME.V1
{
    /// <summary>
    /// Read-only proxy that counts only planner-visible public grid-accessor calls.
    /// Calls made internally by the wrapped grid are deliberately not double-counted.
    /// </summary>
    public sealed class Gate14ReMECountingGridV1 : IReadOnlyNavigationGrid
    {
        private readonly IReadOnlyNavigationGrid inner;
        private bool windowOpen;
        private long containsCalls;
        private long isWalkableCalls;
        private long getTraversalCostCalls;

        public int Width { get { return inner.Width; } }
        public int Height { get { return inner.Height; } }
        public long Version { get { return inner.Version; } }

        public Gate14ReMECountingGridV1(IReadOnlyNavigationGrid inner)
        {
            this.inner = inner ?? throw new ArgumentNullException("inner");
        }

        public bool Contains(GridCoordinate coordinate)
        {
            if (windowOpen) containsCalls = checked(containsCalls + 1L);
            return inner.Contains(coordinate);
        }

        public bool IsWalkable(GridCoordinate coordinate)
        {
            if (windowOpen) isWalkableCalls = checked(isWalkableCalls + 1L);
            return inner.IsWalkable(coordinate);
        }

        public float GetTraversalCost(GridCoordinate coordinate)
        {
            if (windowOpen) getTraversalCostCalls = checked(getTraversalCostCalls + 1L);
            return inner.GetTraversalCost(coordinate);
        }

        public void BeginWindow()
        {
            if (windowOpen) throw new InvalidOperationException("A grid-counter window is already open.");
            containsCalls = 0L;
            isWalkableCalls = 0L;
            getTraversalCostCalls = 0L;
            windowOpen = true;
        }

        public Gate14ReMEGridCounterSnapshotV1 EndWindow()
        {
            if (!windowOpen) throw new InvalidOperationException("No grid-counter window is open.");
            windowOpen = false;
            return new Gate14ReMEGridCounterSnapshotV1
            {
                containsCalls = containsCalls,
                isWalkableCalls = isWalkableCalls,
                getTraversalCostCalls = getTraversalCostCalls,
                totalCalls = checked(checked(containsCalls + isWalkableCalls) + getTraversalCostCalls)
            };
        }
    }

    public static class Gate14ReMEAllocationCounterV1
    {
        public const string CounterId = "GC.GetAllocatedBytesForCurrentThread-v1";

        public static long Capture()
        {
            long value = GC.GetAllocatedBytesForCurrentThread();
            if (value < 0L) throw new InvalidOperationException("The allocation counter returned a negative value.");
            return value;
        }

        public static long Difference(long before, long after)
        {
            if (before < 0L || after < before)
            {
                throw new InvalidOperationException("The allocation counter was non-monotonic.");
            }
            return checked(after - before);
        }
    }

    public static class Gate14ReMEProcessResourcesV1
    {
        public static Gate14ReMEProcessResourceRawV1 Capture(
            string recordId,
            string inputId,
            string superblockId,
            string anonymousLaneId,
            string identityBindingSha256,
            string measurementPointId,
            int eventGroupIndex,
            string sourceRelativePath,
            string sourceSha256)
        {
            using (Process process = Process.GetCurrentProcess())
            {
                process.Refresh();
                return new Gate14ReMEProcessResourceRawV1
                {
                    recordId = recordId,
                    inputId = inputId,
                    superblockId = superblockId,
                    anonymousLaneId = anonymousLaneId,
                    identityBindingSha256 = identityBindingSha256,
                    measurementPointId = measurementPointId,
                    eventGroupIndex = eventGroupIndex,
                    processId = process.Id,
                    privateMemoryBytes = process.PrivateMemorySize64,
                    workingSetBytes = process.WorkingSet64,
                    managedMemoryBytes = GC.GetTotalMemory(false),
                    peakWorkingSetBytes = process.PeakWorkingSet64,
                    capturedAtUtc = DateTime.UtcNow.ToString("o"),
                    sourceRelativePath = sourceRelativePath,
                    sourceSha256 = sourceSha256
                };
            }
        }
    }

    /// <summary>
    /// Frozen logical-capacity sizer. It reads state through reflection without
    /// mutating planners. The formula intentionally reports logical owned capacity,
    /// not CLR object headers, allocator overhead, RSS, or total managed heap.
    /// </summary>
    public static class Gate14ReMEPersistentStateSizerV1
    {
        public const string FormulaId = "gate14re-me-persistent-state-logical-capacity-v1";

        private const int BoolBytes = 1;
        private const int Int32Bytes = 4;
        private const int Int64Bytes = 8;
        private const int DoubleBytes = 8;
        private const int GridCoordinateBytes = 8;
        private const int NavigationGridChangeBytes = 16;
        private const int DStarOrLpaKeyNodeBytes = 48;
        private const int CffIntegrationNodeBytes = 48;
        private const int IdffRepairNodeBytes = 56;

        public static Gate14ReMEPersistentStateRawV1[] Measure(
            INavigationPlanner planner,
            string inputId,
            string superblockId,
            string anonymousLaneId,
            string identityBindingSha256,
            string measurementPointId,
            int eventGroupIndex,
            string sourceRelativePath,
            string sourceSha256)
        {
            if (planner == null) throw new ArgumentNullException("planner");
            List<Component> components = new List<Component>();
            string algorithmId = planner.AlgorithmId;

            AddCollectionCount(components, planner, "declaredGoals", "declaredGoals", GridCoordinateBytes);
            AddCollectionCount(components, planner, "declaredGoalSet", "declaredGoalSet", GridCoordinateBytes);
            AddArray(components, planner, "canonicalGoals", "canonicalGoals", GridCoordinateBytes);

            if (algorithmId == NavigationAlgorithmIds.DStarLite ||
                algorithmId == NavigationAlgorithmIds.LifelongPlanningAStar)
            {
                object statesObject = GetField(planner, "agentStates", true);
                IDictionary states = statesObject as IDictionary;
                if (states == null) throw new InvalidOperationException("agentStates is not an IDictionary.");
                AddNestedArrays(components, states.Values, "G", "agentStates.G", DoubleBytes);
                AddNestedArrays(components, states.Values, "Rhs", "agentStates.Rhs", DoubleBytes);
                AddNestedArrays(components, states.Values, "QueueRevisions", "agentStates.QueueRevisions", Int64Bytes);
                AddNestedQueueArrays(components, states.Values, "Queue", "items", "agentStates.Queue.items", DStarOrLpaKeyNodeBytes);
                AddLogical(components, "agentStates.dictionaryKeys", states.Count, Int32Bytes, "logical-dictionary-keys");
            }
            else if (algorithmId == NavigationAlgorithmIds.CorrectedFullRecomputeFlowField)
            {
                object field = GetField(planner, "field", false);
                if (field != null)
                {
                    AddArray(components, field, "Integration", "field.Integration", DoubleBytes);
                    AddArray(components, field, "HasOwner", "field.HasOwner", BoolBytes);
                    AddArray(components, field, "Owner", "field.Owner", GridCoordinateBytes);
                    AddArray(components, field, "ActiveGoal", "field.ActiveGoal", BoolBytes);
                    AddArray(components, field, "HasDirection", "field.HasDirection", BoolBytes);
                    AddArray(components, field, "Next", "field.Next", GridCoordinateBytes);
                }
            }
            else if (algorithmId == NavigationAlgorithmIds.IncrementalDynamicFlowField)
            {
                AddArray(components, planner, "gCost", "gCost", DoubleBytes);
                AddArray(components, planner, "gHasOwner", "gHasOwner", BoolBytes);
                AddArray(components, planner, "gOwner", "gOwner", GridCoordinateBytes);
                AddArray(components, planner, "rhsCost", "rhsCost", DoubleBytes);
                AddArray(components, planner, "rhsHasOwner", "rhsHasOwner", BoolBytes);
                AddArray(components, planner, "rhsOwner", "rhsOwner", GridCoordinateBytes);
                AddArray(components, planner, "activeGoal", "activeGoal", BoolBytes);
                AddArray(components, planner, "hasDirection", "hasDirection", BoolBytes);
                AddArray(components, planner, "next", "next", GridCoordinateBytes);
                AddArray(components, planner, "queueRevisions", "queueRevisions", Int64Bytes);
                AddArray(components, planner, "pendingChanges", "pendingChanges", NavigationGridChangeBytes);
                AddArray(components, planner, "repairCounted", "repairCounted", BoolBytes);
                AddArray(components, planner, "directionDirty", "directionDirty", BoolBytes);
                AddListCapacity(components, planner, "directionDirtyIndices", "directionDirtyIndices", Int32Bytes);
                object queue = GetField(planner, "queue", false);
                if (queue != null) AddArray(components, queue, "items", "queue.items", IdffRepairNodeBytes);
            }
            else if (algorithmId != NavigationAlgorithmIds.AStarRepeated &&
                     algorithmId != NavigationAlgorithmIds.BidirectionalAStarRepeated)
            {
                throw new NotSupportedException("No frozen D4 sizing formula exists for " + algorithmId + ".");
            }

            long total = 0L;
            for (int index = 0; index < components.Count; index++)
            {
                total = checked(total + components[index].Bytes);
            }

            Gate14ReMEPersistentStateRawV1[] rows = new Gate14ReMEPersistentStateRawV1[components.Count];
            for (int index = 0; index < components.Count; index++)
            {
                Component component = components[index];
                rows[index] = new Gate14ReMEPersistentStateRawV1
                {
                    recordId = string.Format("{0}:{1}:state:{2}:{3}", inputId, anonymousLaneId, measurementPointId, index),
                    inputId = inputId,
                    superblockId = superblockId,
                    anonymousLaneId = anonymousLaneId,
                    identityBindingSha256 = identityBindingSha256,
                    measurementPointId = measurementPointId,
                    eventGroupIndex = eventGroupIndex,
                    persistentContainerName = component.Name,
                    containerKind = component.Kind,
                    persistentContainerCapacity = component.Capacity,
                    persistentContainerBytesPerElement = component.BytesPerElement,
                    persistentContainerCapacityBytes = component.Bytes,
                    persistentPrimitiveArrayBytes = component.Kind == "array" ? component.Bytes : 0L,
                    persistentStateBytesTotal = total,
                    sizingFormulaId = FormulaId,
                    valid = true,
                    invalidReasonCode = string.Empty,
                    sourceRelativePath = sourceRelativePath,
                    sourceSha256 = sourceSha256
                };
            }
            return rows;
        }

        public static bool RunSyntheticFixture()
        {
            SyntheticFixture fixture = new SyntheticFixture();
            List<Component> components = new List<Component>();
            AddArray(components, fixture, "doubles", "fixture.doubles", DoubleBytes);
            AddArray(components, fixture, "flags", "fixture.flags", BoolBytes);
            AddListCapacity(components, fixture, "indices", "fixture.indices", Int32Bytes);
            return components.Count == 3 &&
                   components[0].Capacity == 7 && components[0].Bytes == 56L &&
                   components[1].Capacity == 11 && components[1].Bytes == 11L &&
                   components[2].Capacity == 13 && components[2].Bytes == 52L;
        }

        private static void AddNestedArrays(List<Component> target, ICollection values, string fieldName, string name, int bytesPerElement)
        {
            long capacity = 0L;
            foreach (object value in values)
            {
                Array array = GetField(value, fieldName, true) as Array;
                if (array == null) throw new InvalidOperationException(name + " is not an array.");
                capacity = checked(capacity + array.LongLength);
            }
            AddLogical(target, name, capacity, bytesPerElement, "array");
        }

        private static void AddNestedQueueArrays(List<Component> target, ICollection values, string queueField, string arrayField, string name, int bytesPerElement)
        {
            long capacity = 0L;
            foreach (object value in values)
            {
                object queue = GetField(value, queueField, false);
                if (queue == null) continue;
                Array array = GetField(queue, arrayField, true) as Array;
                if (array == null) throw new InvalidOperationException(name + " is not an array.");
                capacity = checked(capacity + array.LongLength);
            }
            AddLogical(target, name, capacity, bytesPerElement, "array");
        }

        private static void AddCollectionCount(List<Component> target, object owner, string fieldName, string name, int bytesPerElement)
        {
            object value = GetField(owner, fieldName, false);
            if (value == null) return;
            PropertyInfo countProperty = value.GetType().GetProperty("Count", BindingFlags.Instance | BindingFlags.Public);
            if (countProperty == null || countProperty.PropertyType != typeof(int))
            {
                throw new InvalidOperationException(name + " does not expose an integer Count property.");
            }
            int count = (int)countProperty.GetValue(value, null);
            AddLogical(target, name, count, bytesPerElement, "logical-collection-elements");
        }

        private static void AddArray(List<Component> target, object owner, string fieldName, string name, int bytesPerElement)
        {
            object value = GetField(owner, fieldName, false);
            if (value == null) return;
            Array array = value as Array;
            if (array == null) throw new InvalidOperationException(name + " is not an array.");
            AddLogical(target, name, array.LongLength, bytesPerElement, "array");
        }

        private static void AddListCapacity(List<Component> target, object owner, string fieldName, string name, int bytesPerElement)
        {
            object value = GetField(owner, fieldName, false);
            if (value == null) return;
            PropertyInfo capacityProperty = value.GetType().GetProperty("Capacity", BindingFlags.Instance | BindingFlags.Public);
            if (capacityProperty == null) throw new InvalidOperationException(name + " does not expose Capacity.");
            int capacity = (int)capacityProperty.GetValue(value, null);
            AddLogical(target, name, capacity, bytesPerElement, "list-capacity");
        }

        private static void AddLogical(List<Component> target, string name, long capacity, int bytesPerElement, string kind)
        {
            if (capacity < 0L || bytesPerElement <= 0) throw new InvalidOperationException("Invalid D4 capacity formula input.");
            target.Add(new Component(name, kind, capacity, bytesPerElement, checked(capacity * bytesPerElement)));
        }

        private static object GetField(object owner, string fieldName, bool required)
        {
            if (owner == null)
            {
                if (required) throw new InvalidOperationException("Cannot inspect " + fieldName + " on a null owner.");
                return null;
            }
            FieldInfo field = owner.GetType().GetField(fieldName, BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
            if (field == null)
            {
                if (required) throw new InvalidOperationException("Frozen D4 field is missing: " + owner.GetType().FullName + "." + fieldName);
                return null;
            }
            return field.GetValue(owner);
        }

        private sealed class Component
        {
            public readonly string Name;
            public readonly string Kind;
            public readonly long Capacity;
            public readonly int BytesPerElement;
            public readonly long Bytes;

            public Component(string name, string kind, long capacity, int bytesPerElement, long bytes)
            {
                Name = name;
                Kind = kind;
                Capacity = capacity;
                BytesPerElement = bytesPerElement;
                Bytes = bytes;
            }
        }

        private sealed class SyntheticFixture
        {
            private readonly double[] doubles = new double[7];
            private readonly bool[] flags = new bool[11];
            private readonly List<int> indices = new List<int>(13);
        }
    }
}
