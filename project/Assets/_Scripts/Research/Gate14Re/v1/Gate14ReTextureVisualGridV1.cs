using System;
using DDM.Research.Navigation;
using UnityEngine;

namespace DDM.Research.Gate14Re.V1
{
    /// <summary>Rendered walkability/cost representation used by the live preflight and formal runner.</summary>
    public sealed class Gate14ReTextureVisualGridV1 : IGate14ReVisualGridSynchronizerV1, IDisposable
    {
        private readonly Renderer targetRenderer;
        private Texture2D texture;
        private Material material;
        private int width;
        private int height;

        public long VisualRevision { get; private set; }
        public Texture2D Texture { get { return texture; } }

        public Gate14ReTextureVisualGridV1(Renderer targetRenderer)
        {
            this.targetRenderer = targetRenderer ?? throw new ArgumentNullException("targetRenderer");
        }

        public void Initialize(IReadOnlyNavigationGrid grid)
        {
            if (grid == null) throw new ArgumentNullException("grid");
            width = grid.Width;
            height = grid.Height;
            texture = new Texture2D(width, height, TextureFormat.RGBA32, false);
            texture.filterMode = FilterMode.Point;
            texture.wrapMode = TextureWrapMode.Clamp;
            Color[] pixels = new Color[checked(width * height)];
            for (int y = 0; y < height; y++)
            {
                for (int x = 0; x < width; x++)
                {
                    GridCoordinate coordinate = new GridCoordinate(x, y);
                    pixels[y * width + x] = CellColor(grid, coordinate);
                }
            }
            texture.SetPixels(pixels);
            texture.Apply(false, false);

            Shader shader = Shader.Find("Unlit/Texture");
            if (shader == null) shader = Shader.Find("Standard");
            if (shader == null) throw new InvalidOperationException("No supported grid visualization shader is available.");
            material = new Material(shader);
            material.mainTexture = texture;
            targetRenderer.sharedMaterial = material;
            VisualRevision = grid.Version;
        }

        public void ApplyGridChange(IReadOnlyNavigationGrid grid, NavigationChangeSet changeSet)
        {
            if (grid == null) throw new ArgumentNullException("grid");
            if (changeSet == null) throw new ArgumentNullException("changeSet");
            if (texture == null || grid.Width != width || grid.Height != height) throw new InvalidOperationException("Rendered grid is not initialized for the current grid.");
            if (VisualRevision != changeSet.previousGridVersion || grid.Version != changeSet.newGridVersion) throw new InvalidOperationException("Rendered grid received a noncanonical revision transition.");
            for (int index = 0; index < changeSet.changes.Length; index++)
            {
                GridCoordinate coordinate = changeSet.changes[index].coordinate;
                texture.SetPixel(coordinate.x, coordinate.y, CellColor(grid, coordinate));
            }
            texture.Apply(false, false);
            VisualRevision = changeSet.newGridVersion;
        }

        public void Dispose()
        {
            if (material != null) UnityEngine.Object.Destroy(material);
            if (texture != null) UnityEngine.Object.Destroy(texture);
            material = null;
            texture = null;
        }

        private static Color CellColor(IReadOnlyNavigationGrid grid, GridCoordinate coordinate)
        {
            if (!grid.IsWalkable(coordinate)) return new Color(0.055f, 0.06f, 0.07f, 1f);
            float cost = grid.GetTraversalCost(coordinate);
            float weight = Mathf.Clamp01((cost - 1f) / 7f);
            return Color.Lerp(new Color(0.58f, 0.64f, 0.68f, 1f), new Color(0.88f, 0.40f, 0.10f, 1f), weight);
        }
    }
}
