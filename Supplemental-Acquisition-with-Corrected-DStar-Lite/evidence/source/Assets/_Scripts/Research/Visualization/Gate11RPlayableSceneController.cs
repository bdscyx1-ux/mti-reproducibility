using System;
using System.Collections.Generic;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using DDM.Research.Algorithms;
using DDM.Research.Grid;
using DDM.Research.Navigation;
using DDM.Research.Scenarios;
using UnityEngine;

namespace DDM.Research.Visualization
{
    /// <summary>
    /// Deterministic, research-only scene viewer. It replays scenario events by
    /// index and deliberately does not expose timing results as evidence.
    /// </summary>
    public sealed class Gate11RPlayableSceneController : MonoBehaviour
    {
        public string schemaId;
        public string matrixId;
        public string playableBundleId;
        public string scenarioId;
        public string scenarioRelativePath;
        public string scenarioSha256;
        public string scenarioFingerprintSha256;
        public string[] campaignIds = new string[0];
        public string[] eligibleAlgorithmIds = new string[0];
        public string defaultAlgorithmId = NavigationAlgorithmIds.AStarRepeated;
        public string directionGlyphId = Gate11RFormalScenarioMatrixGenerator.DirectionGlyphId;
        public string captureLayoutId = Gate11RFormalScenarioMatrixGenerator.CaptureLayoutId;
        public string watermark = Gate11RFormalScenarioMatrixGenerator.VisualizationWatermark;
        public bool visualizationOnly = true;
        public bool timingEvidenceAllowed;
        public int visualizationBlockOrdinal;
        public float autoAdvanceSeconds = 1.5f;

        private LoadedDeterministicScenario loaded;
        private ResolvedDeterministicScenario scenario;
        private ResearchNavigationGrid grid;
        private INavigationPlanner planner;
        private NavigationPlanResult lastPlan;
        private NavigationRepairResult lastRepair;
        private NavigationOperationMetrics initializationMetrics;
        private Texture2D gridTexture;
        private int eventIndex;
        private int selectedAgentIndex;
        private bool playing;
        private float nextAdvanceAt;
        private string activeAlgorithmId;
        private string activeCampaignId;
        private string error = string.Empty;
        private string traceHash = string.Empty;

        public bool IsLoaded { get { return scenario != null && grid != null; } }
        public int EventIndex { get { return eventIndex; } }
        public string ActiveAlgorithmId { get { return activeAlgorithmId ?? string.Empty; } }
        public string ActiveCampaignId { get { return activeCampaignId ?? string.Empty; } }
        public string TraceHash { get { return traceHash ?? string.Empty; } }

        public void Configure(
            string configuredScenarioId,
            string configuredScenarioRelativePath,
            string configuredScenarioSha256,
            string configuredScenarioFingerprint,
            string[] configuredCampaignIds,
            string[] configuredAlgorithms)
        {
            schemaId = "gate11r-playable-scene-controller-v1";
            matrixId = Gate11RFormalScenarioMatrixGenerator.MatrixId;
            playableBundleId = Gate11RFormalScenarioMatrixGenerator.PlayableBundleId;
            scenarioId = configuredScenarioId;
            scenarioRelativePath = configuredScenarioRelativePath;
            scenarioSha256 = configuredScenarioSha256;
            scenarioFingerprintSha256 = configuredScenarioFingerprint;
            campaignIds = configuredCampaignIds ?? new string[0];
            eligibleAlgorithmIds = configuredAlgorithms ?? new string[0];
            defaultAlgorithmId = eligibleAlgorithmIds.Length > 0 ? eligibleAlgorithmIds[0] : NavigationAlgorithmIds.AStarRepeated;
            directionGlyphId = Gate11RFormalScenarioMatrixGenerator.DirectionGlyphId;
            captureLayoutId = Gate11RFormalScenarioMatrixGenerator.CaptureLayoutId;
            watermark = Gate11RFormalScenarioMatrixGenerator.VisualizationWatermark;
            visualizationOnly = true;
            timingEvidenceAllowed = false;
            visualizationBlockOrdinal = 0;
        }

        private void Start()
        {
            try
            {
                activeCampaignId = campaignIds != null && campaignIds.Length > 0 ? campaignIds[0] : string.Empty;
                activeAlgorithmId = defaultAlgorithmId;
                if (Gate11RPlayableSelection.HasSelection && string.Equals(Gate11RPlayableSelection.ScenarioId, scenarioId, StringComparison.Ordinal))
                {
                    activeCampaignId = Gate11RPlayableSelection.CampaignId;
                    activeAlgorithmId = Gate11RPlayableSelection.AlgorithmId;
                    visualizationBlockOrdinal = Gate11RPlayableSelection.BlockOrdinal;
                }
                LoadAndReset();
            }
            catch (Exception exception)
            {
                error = exception.ToString();
                Debug.LogException(exception);
            }
        }

        private void Update()
        {
            if (!playing || !IsLoaded || Time.unscaledTime < nextAdvanceAt) return;
            if (eventIndex >= scenario.ScheduledChanges.Count) { playing = false; return; }
            ApplyNextEvent();
            nextAdvanceAt = Time.unscaledTime + Mathf.Max(0.05f, autoAdvanceSeconds);
        }

        private void OnDestroy()
        {
            if (planner != null) planner.Reset();
            if (gridTexture != null) Destroy(gridTexture);
        }

        public void LoadAndReset()
        {
            string projectRoot = Directory.GetParent(Application.dataPath).FullName;
            string fullPath = Path.GetFullPath(Path.Combine(projectRoot, scenarioRelativePath.Replace('/', Path.DirectorySeparatorChar)));
            loaded = DeterministicScenarioJson.LoadFromFile(fullPath);
            if (!string.Equals(loaded.Resolved.ScenarioId, scenarioId, StringComparison.Ordinal)) throw new InvalidDataException("Scene scenario id differs from the canonical scenario.");
            if (!string.Equals(loaded.SourceSha256, scenarioSha256, StringComparison.Ordinal)) throw new InvalidDataException("Scene scenario SHA-256 differs from the canonical scenario.");
            if (!string.Equals(loaded.Resolved.FingerprintSha256, scenarioFingerprintSha256, StringComparison.Ordinal)) throw new InvalidDataException("Scene scenario fingerprint differs from the canonical scenario.");
            scenario = loaded.Resolved;
            selectedAgentIndex = Mathf.Clamp(selectedAgentIndex, 0, Math.Max(0, scenario.Agents.Count - 1));
            eventIndex = 0;
            playing = false;
            error = string.Empty;
            ResetPlannerAndPlan();
        }

        public void RestartReplay()
        {
            LoadAndReset();
        }

        public void SingleStep()
        {
            ApplyNextEvent();
        }

        public void NextEvent()
        {
            ApplyNextEvent();
        }

        public void SeekEventIndex(int targetIndex)
        {
            if (!IsLoaded) return;
            int clamped = Mathf.Clamp(targetIndex, 0, scenario.ScheduledChanges.Count);
            if (clamped < eventIndex) LoadAndReset();
            while (eventIndex < clamped) ApplyNextEvent();
        }

        public void SelectAlgorithm(string algorithmId)
        {
            if (!Contains(eligibleAlgorithmIds, algorithmId)) throw new InvalidOperationException("Algorithm is not eligible for this scenario scene: " + algorithmId);
            activeAlgorithmId = algorithmId;
            ResetPlannerAndPlan();
        }

        private void ApplyNextEvent()
        {
            if (!IsLoaded || eventIndex >= scenario.ScheduledChanges.Count) { playing = false; return; }
            ResolvedScheduledNavigationChange scheduled = scenario.ScheduledChanges[eventIndex];
            NavigationChangeSet changeSet = grid.ApplyChanges(scheduled.EventId, grid.Version, scheduled.Changes);
            lastRepair = planner.ApplyChanges(changeSet, scheduled.RepairBudgetMilliseconds);
            eventIndex++;
            PlanSelectedAgent();
            RebuildTextureAndTrace();
        }

        private void ResetPlannerAndPlan()
        {
            if (planner != null) planner.Reset();
            grid = scenario.CreateGrid();
            for (int index = 0; index < eventIndex; index++)
            {
                ResolvedScheduledNavigationChange scheduled = scenario.ScheduledChanges[index];
                grid.ApplyChanges(scheduled.EventId, grid.Version, scheduled.Changes);
            }
            planner = CreatePlanner(activeAlgorithmId);
            string runId = "gate11r-visual-" + scenario.ScenarioId + "-" + SafeId(activeAlgorithmId);
            initializationMetrics = planner.Initialize(grid, new NavigationPlannerInitialization
            {
                runId = runId,
                goalSetId = scenario.GoalSetId,
                goals = CopyGoals(scenario.Goals),
                connectivity = scenario.Connectivity,
                allowDiagonalCornerCutting = scenario.AllowDiagonalCornerCutting,
                budgetMilliseconds = scenario.InitializationBudgetMilliseconds
            });
            lastRepair = null;
            PlanSelectedAgent();
            RebuildTextureAndTrace();
        }

        private void PlanSelectedAgent()
        {
            if (scenario.Agents.Count == 0) { lastPlan = null; return; }
            selectedAgentIndex = Mathf.Clamp(selectedAgentIndex, 0, scenario.Agents.Count - 1);
            ResolvedScenarioAgent agent = scenario.Agents[selectedAgentIndex];
            lastPlan = planner.Plan(new NavigationPlanRequest
            {
                runId = "gate11r-visual-" + scenario.ScenarioId + "-" + SafeId(activeAlgorithmId),
                requestId = "visual-agent-" + agent.AgentId + "-event-" + eventIndex,
                goalSetId = scenario.GoalSetId,
                agentId = agent.AgentId,
                start = agent.Start,
                goal = agent.Goal,
                expectedGridVersion = grid.Version,
                budgetMilliseconds = scenario.DefaultPlanBudgetMilliseconds
            });
        }

        private void RebuildTextureAndTrace()
        {
            if (gridTexture == null || gridTexture.width != grid.Width || gridTexture.height != grid.Height)
            {
                if (gridTexture != null) Destroy(gridTexture);
                gridTexture = new Texture2D(grid.Width, grid.Height, TextureFormat.RGBA32, false);
                gridTexture.filterMode = FilterMode.Point;
                gridTexture.wrapMode = TextureWrapMode.Clamp;
            }
            Color[] pixels = new Color[grid.Width * grid.Height];
            for (int y = 0; y < grid.Height; y++)
            {
                for (int x = 0; x < grid.Width; x++)
                {
                    GridCoordinate coordinate = new GridCoordinate(x, y);
                    Color color;
                    if (!grid.IsWalkable(coordinate)) color = new Color(0.08f, 0.08f, 0.09f, 1f);
                    else
                    {
                        float cost = grid.GetTraversalCost(coordinate);
                        float weighted = Mathf.Clamp01((cost - 1f) / 7f);
                        color = Color.Lerp(new Color(0.83f, 0.86f, 0.89f, 1f), new Color(0.88f, 0.45f, 0.13f, 1f), weighted);
                        double integration;
                        bool reachable;
                        if (TryGetIntegration(coordinate, out integration, out reachable) && reachable)
                        {
                            float field = Mathf.Clamp01(Mathf.Log10(1f + (float)Math.Min(integration, 100000d)) / 5f);
                            color = Color.Lerp(color, new Color(0.12f, 0.45f, 0.9f, 1f), field * 0.55f);
                        }
                    }
                    pixels[y * grid.Width + x] = color;
                }
            }
            MarkAgentsAndPath(pixels);
            gridTexture.SetPixels(pixels);
            gridTexture.Apply(false, false);
            traceHash = ComputeTraceHash();
        }

        private void MarkAgentsAndPath(Color[] pixels)
        {
            for (int index = 0; index < scenario.Goals.Count; index++) SetPixel(pixels, scenario.Goals[index], new Color(0.15f, 0.86f, 0.3f, 1f));
            for (int index = 0; index < scenario.Agents.Count; index++) SetPixel(pixels, scenario.Agents[index].Start, index == selectedAgentIndex ? Color.magenta : new Color(0.75f, 0.18f, 0.72f, 1f));
            if (lastPlan == null || lastPlan.Path == null) return;
            for (int index = 0; index < lastPlan.Path.Count; index++) SetPixel(pixels, lastPlan.Path[index], Color.yellow);
        }

        private void SetPixel(Color[] pixels, GridCoordinate coordinate, Color color)
        {
            if (grid.Contains(coordinate)) pixels[coordinate.y * grid.Width + coordinate.x] = color;
        }

        private bool TryGetIntegration(GridCoordinate coordinate, out double cost, out bool reachable)
        {
            CorrectedFullRecomputeFlowFieldPlanner cff = planner as CorrectedFullRecomputeFlowFieldPlanner;
            if (cff != null)
            {
                CorrectedFlowFieldCellSnapshot snapshot;
                if (cff.TryGetCellSnapshot(coordinate, out snapshot)) { cost = snapshot.IntegrationCost; reachable = snapshot.Reachable; return true; }
            }
            IncrementalDynamicFlowFieldPlanner idff = planner as IncrementalDynamicFlowFieldPlanner;
            if (idff != null)
            {
                IncrementalFlowFieldCellSnapshot snapshot;
                if (idff.TryGetCellSnapshot(coordinate, out snapshot)) { cost = snapshot.IntegrationCost; reachable = snapshot.Reachable; return true; }
            }
            cost = 0d;
            reachable = false;
            return false;
        }

        private bool TryGetDirection(GridCoordinate coordinate, out GridCoordinate next)
        {
            CorrectedFullRecomputeFlowFieldPlanner cff = planner as CorrectedFullRecomputeFlowFieldPlanner;
            if (cff != null)
            {
                CorrectedFlowFieldCellSnapshot snapshot;
                if (cff.TryGetCellSnapshot(coordinate, out snapshot) && snapshot.HasDirection) { next = snapshot.Next; return true; }
            }
            IncrementalDynamicFlowFieldPlanner idff = planner as IncrementalDynamicFlowFieldPlanner;
            if (idff != null)
            {
                IncrementalFlowFieldCellSnapshot snapshot;
                if (idff.TryGetCellSnapshot(coordinate, out snapshot) && snapshot.HasDirection) { next = snapshot.Next; return true; }
            }
            next = coordinate;
            return false;
        }

        private void OnGUI()
        {
            GUI.depth = -100;
            GUILayout.BeginArea(new Rect(12f, 12f, 430f, Screen.height - 24f), GUI.skin.box);
            GUILayout.Label("Gate 11R deterministic experiment viewer");
            GUILayout.Label(watermark);
            if (!string.IsNullOrEmpty(error)) { GUILayout.Label(error); GUILayout.EndArea(); return; }
            if (!IsLoaded) { GUILayout.Label("Loading canonical scenario..."); GUILayout.EndArea(); return; }
            GUILayout.Label("Scenario: " + scenario.ScenarioId + " | seed " + scenario.RandomSeed);
            GUILayout.Label("Campaign: " + activeCampaignId);
            GUILayout.Label("Algorithm: " + activeAlgorithmId + " | block " + visualizationBlockOrdinal);
            GUILayout.Label("Williams: " + WilliamsDescription(activeCampaignId, activeAlgorithmId, visualizationBlockOrdinal));
            GUILayout.Label("Event: " + eventIndex + "/" + scenario.ScheduledChanges.Count + " | grid v" + grid.Version);
            GUILayout.Label("Scenario fingerprint: " + ShortHash(scenario.FingerprintSha256));
            GUILayout.Label("Trace: " + ShortHash(traceHash));
            GUILayout.BeginHorizontal();
            if (GUILayout.Button(playing ? "Pause" : "Play")) { playing = !playing; nextAdvanceAt = Time.unscaledTime + autoAdvanceSeconds; }
            if (GUILayout.Button("Single Step")) SingleStep();
            if (GUILayout.Button("Next Event")) NextEvent();
            if (GUILayout.Button("Restart")) RestartReplay();
            GUILayout.EndHorizontal();
            int seek = Mathf.RoundToInt(GUILayout.HorizontalSlider(eventIndex, 0, scenario.ScheduledChanges.Count));
            if (seek != eventIndex) SeekEventIndex(seek);
            GUILayout.Label("Deterministic seek: " + seek);
            GUILayout.Label("Agent index: " + selectedAgentIndex + "/" + Math.Max(0, scenario.Agents.Count - 1));
            int agent = Mathf.RoundToInt(GUILayout.HorizontalSlider(selectedAgentIndex, 0, Math.Max(0, scenario.Agents.Count - 1)));
            if (agent != selectedAgentIndex) { selectedAgentIndex = agent; PlanSelectedAgent(); RebuildTextureAndTrace(); }
            GUILayout.BeginHorizontal();
            for (int index = 0; index < eligibleAlgorithmIds.Length; index++)
            {
                string candidate = eligibleAlgorithmIds[index];
                if (GUILayout.Button(candidate)) SelectAlgorithm(candidate);
            }
            GUILayout.EndHorizontal();
            if (lastPlan != null)
            {
                GUILayout.Label("Plan: " + lastPlan.Status + " / " + lastPlan.FailureReason + " | path " + lastPlan.Path.Count);
                GUILayout.Label("Expanded " + lastPlan.Metrics.expandedNodes + " | repaired " + (lastRepair == null ? 0 : lastRepair.Metrics.repairedCells));
            }
            GUILayout.Label("Init processed cells: " + (initializationMetrics == null ? 0 : initializationMetrics.processedNodesOrCells));
            GUILayout.Label("Layers: grid + costs + starts/goals + path + integration/direction + aggregate work");
            GUILayout.Label("Direction glyph: " + directionGlyphId + " | capture: " + captureLayoutId);
            GUILayout.EndArea();

            if (gridTexture == null) return;
            float availableWidth = Mathf.Max(32f, Screen.width - 470f);
            float availableHeight = Mathf.Max(32f, Screen.height - 40f);
            float scale = Mathf.Min(availableWidth / grid.Width, availableHeight / grid.Height);
            Rect gridRect = new Rect(458f, 20f, grid.Width * scale, grid.Height * scale);
            GUI.DrawTexture(gridRect, gridTexture, ScaleMode.StretchToFill, false);
            DrawDirectionGlyphs(gridRect, scale);
        }

        private void DrawDirectionGlyphs(Rect rect, float scale)
        {
            if (!(planner is CorrectedFullRecomputeFlowFieldPlanner) && !(planner is IncrementalDynamicFlowFieldPlanner)) return;
            int stride = Math.Max(1, Math.Max(grid.Width, grid.Height) / 24);
            GUIStyle style = new GUIStyle(GUI.skin.label) { alignment = TextAnchor.MiddleCenter, fontSize = Mathf.Clamp(Mathf.RoundToInt(scale * stride * 0.55f), 8, 20) };
            style.normal.textColor = Color.white;
            for (int y = 0; y < grid.Height; y += stride)
            {
                for (int x = 0; x < grid.Width; x += stride)
                {
                    GridCoordinate current = new GridCoordinate(x, y);
                    GridCoordinate next;
                    if (!TryGetDirection(current, out next)) continue;
                    string glyph = DirectionGlyph(next.x - x, next.y - y);
                    float px = rect.x + x * scale;
                    float py = rect.y + (grid.Height - 1 - y) * scale;
                    GUI.Label(new Rect(px, py, scale * stride, scale * stride), glyph, style);
                }
            }
        }

        private string ComputeTraceHash()
        {
            StringBuilder builder = new StringBuilder();
            builder.Append(scenarioId).Append('|').Append(activeCampaignId).Append('|').Append(activeAlgorithmId).Append('|');
            builder.Append(eventIndex).Append('|').Append(grid.Version).Append('|').Append(selectedAgentIndex).Append('|');
            if (lastPlan != null)
            {
                builder.Append(lastPlan.Status).Append('|').Append(lastPlan.FailureReason).Append('|');
                for (int index = 0; index < lastPlan.Path.Count; index++) builder.Append(lastPlan.Path[index].x).Append(',').Append(lastPlan.Path[index].y).Append(';');
            }
            SHA256 sha = SHA256.Create();
            try { return BitConverter.ToString(sha.ComputeHash(Encoding.UTF8.GetBytes(builder.ToString()))).Replace("-", string.Empty).ToLowerInvariant(); }
            finally { sha.Dispose(); }
        }

        private static INavigationPlanner CreatePlanner(string algorithmId)
        {
            if (algorithmId == NavigationAlgorithmIds.AStarRepeated) return new AStarRepeatedPlanner();
            if (algorithmId == NavigationAlgorithmIds.DStarLite) return new DStarLitePlanner();
            if (algorithmId == NavigationAlgorithmIds.CorrectedFullRecomputeFlowField) return new CorrectedFullRecomputeFlowFieldPlanner();
            if (algorithmId == NavigationAlgorithmIds.IncrementalDynamicFlowField) return new IncrementalDynamicFlowFieldPlanner();
            throw new ArgumentOutOfRangeException("algorithmId", algorithmId, "Unknown navigation algorithm.");
        }

        private static GridCoordinate[] CopyGoals(IReadOnlyList<GridCoordinate> goals)
        {
            GridCoordinate[] result = new GridCoordinate[goals.Count];
            for (int index = 0; index < result.Length; index++) result[index] = goals[index];
            return result;
        }

        private static bool Contains(string[] values, string value)
        {
            if (values == null) return false;
            for (int index = 0; index < values.Length; index++) if (string.Equals(values[index], value, StringComparison.Ordinal)) return true;
            return false;
        }

        private static string SafeId(string value)
        {
            return (value ?? string.Empty).Replace("*", "star").Replace(" ", "-").Replace("/", "-").ToLowerInvariant();
        }

        private static string ShortHash(string value)
        {
            return string.IsNullOrEmpty(value) || value.Length <= 16 ? value : value.Substring(0, 16);
        }

        private static string DirectionGlyph(int dx, int dy)
        {
            if (dx == 0 && dy > 0) return "^";
            if (dx == 0 && dy < 0) return "v";
            if (dx > 0 && dy == 0) return ">";
            if (dx < 0 && dy == 0) return "<";
            if (dx > 0 && dy > 0) return "/";
            if (dx < 0 && dy < 0) return "/";
            if (dx > 0 && dy < 0) return "\\";
            if (dx < 0 && dy > 0) return "\\";
            return ".";
        }

        private static string WilliamsDescription(string campaignId, string algorithmId, int blockOrdinal)
        {
            string[][] rows;
            if (campaignId != null && campaignId.EndsWith("--shared", StringComparison.Ordinal))
            {
                rows = new[]
                {
                    new[] { "A*-R", "D*L", "IDFF", "C-FF" },
                    new[] { "D*L", "C-FF", "A*-R", "IDFF" },
                    new[] { "C-FF", "IDFF", "D*L", "A*-R" },
                    new[] { "IDFF", "A*-R", "C-FF", "D*L" }
                };
            }
            else if (campaignId != null && campaignId.EndsWith("--per-agent", StringComparison.Ordinal))
                rows = new[] { new[] { "A*-R", "D*L" }, new[] { "D*L", "A*-R" } };
            else rows = new[] { new[] { "C-FF", "IDFF" }, new[] { "IDFF", "C-FF" } };
            string[] row = rows[Math.Abs(blockOrdinal) % rows.Length];
            int position = Array.IndexOf(row, algorithmId);
            string predecessor = position > 0 ? row[position - 1] : "none";
            return "row " + (Math.Abs(blockOrdinal) % rows.Length) + ", position " + (position + 1) + ", predecessor " + predecessor;
        }
    }
}
