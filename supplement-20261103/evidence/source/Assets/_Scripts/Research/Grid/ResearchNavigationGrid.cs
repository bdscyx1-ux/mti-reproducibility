using System;
using System.Collections.Generic;
using DDM.Research.Navigation;
using UnityEngine;

namespace DDM.Research.Grid
{
    /// <summary>
    /// Versioned, scene-independent grid used by research planners.
    /// Runtime changes are validated atomically and returned in a canonical order.
    /// </summary>
    public sealed class ResearchNavigationGrid : IReadOnlyNavigationGrid
    {
        private readonly bool[] walkable;
        private readonly float[] traversalCosts;
        private long version;

        public int Width { get; private set; }
        public int Height { get; private set; }
        public long Version { get { return version; } }

        public ResearchNavigationGrid(
            int width,
            int height,
            float defaultTraversalCost = 1f,
            IReadOnlyList<NavigationGridChange> initialOverrides = null)
        {
            if (width <= 0) throw new ArgumentOutOfRangeException("width");
            if (height <= 0) throw new ArgumentOutOfRangeException("height");
            ValidateTraversalCost(defaultTraversalCost, "defaultTraversalCost");

            int cellCount;
            try { cellCount = checked(width * height); }
            catch (OverflowException)
            {
                throw new ArgumentOutOfRangeException("width", "Grid dimensions exceed the supported cell count.");
            }

            Width = width;
            Height = height;
            walkable = new bool[cellCount];
            traversalCosts = new float[cellCount];
            for (int index = 0; index < cellCount; index++)
            {
                walkable[index] = true;
                traversalCosts[index] = defaultTraversalCost;
            }

            if (initialOverrides != null && initialOverrides.Count > 0)
            {
                NavigationGridChange[] normalized = NormalizeAndValidate(initialOverrides, false);
                ApplyNormalized(normalized);
            }

            version = 0;
        }

        private ResearchNavigationGrid(int width, int height, bool[] walkable, float[] traversalCosts, long version)
        {
            Width = width;
            Height = height;
            this.walkable = walkable;
            this.traversalCosts = traversalCosts;
            this.version = version;
        }

        public bool Contains(GridCoordinate coordinate)
        {
            return coordinate.x >= 0 && coordinate.x < Width && coordinate.y >= 0 && coordinate.y < Height;
        }

        public bool IsWalkable(GridCoordinate coordinate)
        {
            return Contains(coordinate) && walkable[ToIndex(coordinate)];
        }

        public float GetTraversalCost(GridCoordinate coordinate)
        {
            EnsureContained(coordinate, "coordinate");
            return traversalCosts[ToIndex(coordinate)];
        }

        public ResearchNavigationGrid Clone()
        {
            return new ResearchNavigationGrid(
                Width,
                Height,
                (bool[])walkable.Clone(),
                (float[])traversalCosts.Clone(),
                Version);
        }

        public NavigationChangeSet ApplyChanges(
            string changeSetId,
            long expectedGridVersion,
            IReadOnlyList<NavigationGridChange> changes)
        {
            if (string.IsNullOrWhiteSpace(changeSetId)) throw new ArgumentException("Change-set id is required.", "changeSetId");
            if (expectedGridVersion != Version)
            {
                throw new InvalidOperationException(string.Format(
                    "Expected grid version {0}, but the current version is {1}.",
                    expectedGridVersion,
                    Version));
            }

            NavigationGridChange[] normalized = NormalizeAndValidate(changes, false);
            long previousVersion = Version;
            long newVersion = checked(previousVersion + 1);
            ApplyNormalized(normalized);
            version = newVersion;

            return new NavigationChangeSet
            {
                changeSetId = changeSetId,
                previousGridVersion = previousVersion,
                newGridVersion = newVersion,
                changes = normalized
            };
        }

        private NavigationGridChange[] NormalizeAndValidate(IReadOnlyList<NavigationGridChange> changes, bool allowEmpty)
        {
            if (changes == null) throw new ArgumentNullException("changes");
            if (!allowEmpty && changes.Count == 0) throw new ArgumentException("At least one grid change is required.", "changes");

            NavigationGridChange[] normalized = new NavigationGridChange[changes.Count];
            HashSet<GridCoordinate> seen = new HashSet<GridCoordinate>();
            for (int index = 0; index < changes.Count; index++)
            {
                NavigationGridChange change = changes[index];
                EnsureContained(change.coordinate, "changes");
                ValidateTraversalCost(change.traversalCost, "changes");
                if (!seen.Add(change.coordinate))
                {
                    throw new ArgumentException("A change set cannot contain the same coordinate more than once: " + change.coordinate, "changes");
                }
                normalized[index] = change;
            }

            Array.Sort(normalized, CompareChanges);
            return normalized;
        }

        private void ApplyNormalized(NavigationGridChange[] changes)
        {
            for (int index = 0; index < changes.Length; index++)
            {
                NavigationGridChange change = changes[index];
                int cellIndex = ToIndex(change.coordinate);
                walkable[cellIndex] = change.isWalkable;
                traversalCosts[cellIndex] = change.traversalCost;
            }
        }

        private int ToIndex(GridCoordinate coordinate)
        {
            return (coordinate.y * Width) + coordinate.x;
        }

        private void EnsureContained(GridCoordinate coordinate, string parameterName)
        {
            if (!Contains(coordinate))
            {
                throw new ArgumentOutOfRangeException(parameterName, "Grid coordinate is outside the research grid: " + coordinate);
            }
        }

        private static void ValidateTraversalCost(float cost, string parameterName)
        {
            if (float.IsNaN(cost) || float.IsInfinity(cost) || cost <= 0f)
            {
                throw new ArgumentOutOfRangeException(parameterName, "Traversal cost must be finite and greater than zero.");
            }
        }

        private static int CompareChanges(NavigationGridChange left, NavigationGridChange right)
        {
            int yComparison = left.coordinate.y.CompareTo(right.coordinate.y);
            return yComparison != 0 ? yComparison : left.coordinate.x.CompareTo(right.coordinate.x);
        }
    }

    /// <summary>
    /// Maps grid Y to world Z. Origin is the minimum X/Z corner of cell (0, 0).
    /// </summary>
    [Serializable]
    public sealed class ResearchGridWorldTransform
    {
        public Vector3 origin;
        public float cellSize = 1f;

        public ResearchGridWorldTransform() { }

        public ResearchGridWorldTransform(Vector3 origin, float cellSize)
        {
            this.origin = origin;
            this.cellSize = cellSize;
            Validate();
        }

        public void Validate()
        {
            if (!IsFinite(origin.x) || !IsFinite(origin.y) || !IsFinite(origin.z))
            {
                throw new InvalidOperationException("Grid world origin must contain finite components.");
            }
            if (!IsFinite(cellSize) || cellSize <= 0f)
            {
                throw new InvalidOperationException("Grid cell size must be finite and greater than zero.");
            }
        }

        public bool TryWorldToGrid(Vector3 worldPosition, int gridWidth, int gridHeight, out GridCoordinate coordinate)
        {
            ValidateDimensions(gridWidth, gridHeight);
            Validate();

            coordinate = new GridCoordinate();
            if (!IsFinite(worldPosition.x) || !IsFinite(worldPosition.z)) return false;

            double normalizedX = ((double)worldPosition.x - origin.x) / cellSize;
            double normalizedY = ((double)worldPosition.z - origin.z) / cellSize;
            if (!IsFinite(normalizedX) || !IsFinite(normalizedY) ||
                normalizedX < 0d || normalizedX >= gridWidth ||
                normalizedY < 0d || normalizedY >= gridHeight)
            {
                return false;
            }

            int x = Mathf.FloorToInt((float)normalizedX);
            int y = Mathf.FloorToInt((float)normalizedY);
            coordinate = new GridCoordinate(x, y);
            return true;
        }

        public Vector3 GridToWorldCenter(GridCoordinate coordinate, int gridWidth, int gridHeight)
        {
            ValidateDimensions(gridWidth, gridHeight);
            Validate();
            if (coordinate.x < 0 || coordinate.x >= gridWidth || coordinate.y < 0 || coordinate.y >= gridHeight)
            {
                throw new ArgumentOutOfRangeException("coordinate");
            }

            return new Vector3(
                origin.x + ((coordinate.x + 0.5f) * cellSize),
                origin.y,
                origin.z + ((coordinate.y + 0.5f) * cellSize));
        }

        private static void ValidateDimensions(int width, int height)
        {
            if (width <= 0) throw new ArgumentOutOfRangeException("width");
            if (height <= 0) throw new ArgumentOutOfRangeException("height");
        }

        private static bool IsFinite(float value)
        {
            return !float.IsNaN(value) && !float.IsInfinity(value);
        }

        private static bool IsFinite(double value)
        {
            return !double.IsNaN(value) && !double.IsInfinity(value);
        }
    }
}
