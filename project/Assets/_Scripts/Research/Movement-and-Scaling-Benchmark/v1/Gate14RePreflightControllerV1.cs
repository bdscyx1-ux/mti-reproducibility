using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;
using DDM.Research.Algorithms;
using DDM.Research.Grid;
using DDM.Research.Navigation;
using DDM.Research.Scenarios;
using UnityEngine;
using UnityEngine.AI;

namespace DDM.Research.Gate14Re.V1
{
    public sealed class Gate14RePreflightControllerV1 : MonoBehaviour
    {
        public GameObject unitVisualPrefab;

        private readonly List<GameObject> unitObjects = new List<GameObject>();
        private Gate14ReMovementKernelV1 movement;
        private Gate14ReTextureVisualGridV1 textureVisual;
        private Gate14RePreparedScenario prepared;
        private string mode;
        private string outputPath;
        private int targetRenderedFrames;
        private int renderedFrames;
        private bool finishing;
        private string algorithmId;

        private void Start()
        {
            try
            {
                Dictionary<string, string> arguments = ParseArguments(Environment.GetCommandLineArgs());
                mode = Required(arguments, "gate14re-mode");
                outputPath = Path.GetFullPath(Required(arguments, "gate14re-output"));
                string scenarioPath = Path.GetFullPath(Required(arguments, "gate14re-scenario"));
                string scenarioId = Required(arguments, "gate14re-scenario-id");
                string scenarioSha = Required(arguments, "gate14re-scenario-sha256");
                string conditionId = Required(arguments, "gate14re-condition");
                int footprint = ParseInt(Required(arguments, "gate14re-footprint"), "gate14re-footprint");
                int unitCount = ParseInt(Required(arguments, "gate14re-n"), "gate14re-n");
                targetRenderedFrames = ParseInt(Required(arguments, "gate14re-rendered-frames"), "gate14re-rendered-frames");
                if (targetRenderedFrames < 60 || targetRenderedFrames > 2400) throw new ArgumentOutOfRangeException("gate14re-rendered-frames");
                if (mode != "movement" && mode != "resource") throw new InvalidOperationException("Preflight mode must be movement or resource.");
                algorithmId = mode == "movement" ? Required(arguments, "gate14re-algorithm") : string.Empty;

                ConfigureEnvironment();
                LoadedDeterministicScenario loaded = DeterministicScenarioJson.LoadFromFile(scenarioPath);
                prepared = Gate14ReProtocolV1.Prepare(loaded, scenarioId, scenarioSha, conditionId, footprint, unitCount);
                Renderer gridRenderer = CreateGridSurface(prepared.Resolved);
                textureVisual = new Gate14ReTextureVisualGridV1(gridRenderer);
                ConfigureCamera(prepared.Resolved);
                InstantiateUnitVisuals(prepared.Resolved);

                if (mode == "movement")
                {
                    movement = new Gate14ReMovementKernelV1(
                        "gate14re-live-preflight",
                        prepared.Resolved,
                        CreatePlanner(algorithmId),
                        textureVisual);
                    movement.Release();
                }
                else
                {
                    textureVisual.Initialize(prepared.Resolved.CreateGrid());
                }
            }
            catch (Exception exception)
            {
                FinishFailure(exception);
            }
        }

        private void FixedUpdate()
        {
            if (finishing || movement == null) return;
            try
            {
                movement.AdvanceOneFixedTick();
                IReadOnlyList<Gate14ReUnitStateV1> states = movement.Units;
                if (states.Count != unitObjects.Count) throw new InvalidOperationException("Runtime unit-state/render-object count mismatch.");
                for (int index = 0; index < states.Count; index++) unitObjects[index].transform.position = WithVisualHeight(states[index].Position);
            }
            catch (Exception exception)
            {
                FinishFailure(exception);
            }
        }

        private void LateUpdate()
        {
            if (finishing || prepared == null) return;
            renderedFrames++;
            bool movementMinimumReached = movement == null || (movement.CurrentTick >= 10L && movement.StructuralEventRecords.Count >= 2);
            if (renderedFrames >= targetRenderedFrames && movementMinimumReached) FinishSuccess();
        }

        private void FinishSuccess()
        {
            if (finishing) return;
            finishing = true;
            try
            {
                int enabledRenderers = 0;
                for (int index = 0; index < unitObjects.Count; index++)
                {
                    Renderer[] renderers = unitObjects[index].GetComponentsInChildren<Renderer>(true);
                    bool any = false;
                    for (int rendererIndex = 0; rendererIndex < renderers.Length; rendererIndex++) any |= renderers[rendererIndex].enabled && renderers[rendererIndex].gameObject.activeInHierarchy;
                    if (any) enabledRenderers++;
                }
                long gridRevision = movement == null ? textureVisual.VisualRevision : movement.GridVersion;
                bool plannerMatch = movement == null || movement.PlannerGridVersion == movement.GridVersion;
                PreflightMarker marker = new PreflightMarker
                {
                    schema = "gate14re-live-preflight-marker-v1",
                    studyId = "Gate14Re",
                    status = "PASS",
                    mode = mode,
                    unitCount = unitObjects.Count,
                    unitsWithEnabledRenderer = enabledRenderers,
                    renderedFrameCount = renderedFrames,
                    structuralEventCount = movement == null ? 0 : movement.StructuralEventRecords.Count,
                    gridRevision = gridRevision,
                    visualRevision = textureVisual.VisualRevision,
                    gridPlannerVisualRevisionMatch = plannerMatch && textureVisual.VisualRevision == gridRevision,
                    methodIdentitySuppressedInMarker = true,
                    m1ThroughM5SummaryProduced = false,
                    frameTimeOrFpsSummaryProduced = false,
                    rankingWinnerOrSuperiorityProduced = false,
                    formalObservationProduced = false,
                    formalPhaseAStarted = false
                };
                if (marker.unitCount != marker.unitsWithEnabledRenderer || !marker.gridPlannerVisualRevisionMatch) throw new InvalidOperationException("Live preflight structural completion gate failed.");
                WriteJson(outputPath, marker);
                Application.Quit(0);
            }
            catch (Exception exception)
            {
                finishing = false;
                FinishFailure(exception);
            }
        }

        private void FinishFailure(Exception exception)
        {
            if (finishing) return;
            finishing = true;
            try
            {
                FailureMarker marker = new FailureMarker
                {
                    schema = "gate14re-live-preflight-failure-v1",
                    studyId = "Gate14Re",
                    status = "FAIL_CLOSED",
                    mode = string.IsNullOrEmpty(mode) ? "initialization" : mode,
                    exceptionType = exception == null ? "unknown" : exception.GetType().FullName,
                    message = exception == null ? "Unknown preflight failure." : exception.Message,
                    formalObservationProduced = false,
                    formalPhaseAStarted = false
                };
                if (!string.IsNullOrWhiteSpace(outputPath)) WriteJson(outputPath, marker);
            }
            catch { }
            Debug.LogException(exception);
            Application.Quit(1);
        }

        private void InstantiateUnitVisuals(ResolvedDeterministicScenario scenario)
        {
            if (unitVisualPrefab == null) throw new InvalidOperationException("Canonical unit visual prefab is not bound.");
            GameObject root = new GameObject("Gate14Re units");
            root.SetActive(false);
            ResearchGridWorldTransform transform = scenario.CreateWorldTransform();
            for (int index = 0; index < scenario.Agents.Count; index++)
            {
                ResolvedScenarioAgent agent = scenario.Agents[index];
                GameObject instance = Instantiate(unitVisualPrefab, root.transform);
                instance.name = "gate14re-unit-" + agent.AgentId.ToString("D4", CultureInfo.InvariantCulture);
                DisableLegacyMotion(instance);
                instance.transform.position = WithVisualHeight(transform.GridToWorldCenter(agent.Start, scenario.GridWidth, scenario.GridHeight));
                unitObjects.Add(instance);
            }
            root.SetActive(true);
            if (unitObjects.Count != scenario.Agents.Count) throw new InvalidOperationException("Failed to instantiate the full Gate 14Re population.");
        }

        private static void DisableLegacyMotion(GameObject instance)
        {
            MonoBehaviour[] scripts = instance.GetComponentsInChildren<MonoBehaviour>(true);
            for (int index = 0; index < scripts.Length; index++) scripts[index].enabled = false;
            NavMeshAgent[] agents = instance.GetComponentsInChildren<NavMeshAgent>(true);
            for (int index = 0; index < agents.Length; index++) agents[index].enabled = false;
            Collider[] colliders = instance.GetComponentsInChildren<Collider>(true);
            for (int index = 0; index < colliders.Length; index++) colliders[index].enabled = false;
            Rigidbody[] bodies = instance.GetComponentsInChildren<Rigidbody>(true);
            for (int index = 0; index < bodies.Length; index++)
            {
                bodies[index].velocity = Vector3.zero;
                bodies[index].angularVelocity = Vector3.zero;
                bodies[index].isKinematic = true;
                bodies[index].useGravity = false;
            }
        }

        private static Renderer CreateGridSurface(ResolvedDeterministicScenario scenario)
        {
            GameObject surface = GameObject.CreatePrimitive(PrimitiveType.Quad);
            surface.name = "Gate14Re rendered navigation grid";
            Collider collider = surface.GetComponent<Collider>();
            if (collider != null) Destroy(collider);
            float width = scenario.GridWidth * scenario.CellSize;
            float height = scenario.GridHeight * scenario.CellSize;
            surface.transform.position = new Vector3(scenario.WorldOrigin.x + width * 0.5f, scenario.WorldOrigin.y - 0.05f, scenario.WorldOrigin.z + height * 0.5f);
            surface.transform.rotation = Quaternion.Euler(90f, 0f, 0f);
            surface.transform.localScale = new Vector3(width, height, 1f);
            return surface.GetComponent<Renderer>();
        }

        private static void ConfigureCamera(ResolvedDeterministicScenario scenario)
        {
            GameObject cameraObject = new GameObject("Gate14Re top-down camera");
            Camera camera = cameraObject.AddComponent<Camera>();
            float width = scenario.GridWidth * scenario.CellSize;
            float height = scenario.GridHeight * scenario.CellSize;
            float centerX = scenario.WorldOrigin.x + width * 0.5f;
            float centerZ = scenario.WorldOrigin.z + height * 0.5f;
            cameraObject.transform.position = new Vector3(centerX, scenario.WorldOrigin.y + Math.Max(width, height) * 1.2f + 20f, centerZ);
            cameraObject.transform.rotation = Quaternion.Euler(90f, 0f, 0f);
            camera.orthographic = true;
            float aspect = 16f / 9f;
            camera.orthographicSize = Math.Max(height * 0.525f, width * 0.525f / aspect);
            camera.clearFlags = CameraClearFlags.SolidColor;
            camera.backgroundColor = new Color(0.015f, 0.018f, 0.022f, 1f);
            camera.nearClipPlane = 0.1f;
            camera.farClipPlane = Math.Max(width, height) * 3f + 100f;
        }

        private static void ConfigureEnvironment()
        {
            Application.runInBackground = true;
            Application.targetFrameRate = -1;
            QualitySettings.vSyncCount = 0;
            if (QualitySettings.names.Length > 5) QualitySettings.SetQualityLevel(5, true);
            Time.fixedDeltaTime = (float)Gate14ReProtocolV1.FixedStepSeconds;
            Screen.SetResolution(1920, 1080, FullScreenMode.FullScreenWindow);
        }

        private static INavigationPlanner CreatePlanner(string id)
        {
            if (id == NavigationAlgorithmIds.AStarRepeated) return new AStarRepeatedPlanner();
            if (id == NavigationAlgorithmIds.DStarLite) return new DStarLitePlanner();
            if (id == NavigationAlgorithmIds.CorrectedFullRecomputeFlowField) return new CorrectedFullRecomputeFlowFieldPlanner();
            if (id == NavigationAlgorithmIds.IncrementalDynamicFlowField) return new IncrementalDynamicFlowFieldPlanner();
            throw new ArgumentOutOfRangeException("gate14re-algorithm", "Unknown production planner id.");
        }

        private static Vector3 WithVisualHeight(Vector3 position)
        {
            position.y += 1f;
            return position;
        }

        private static Dictionary<string, string> ParseArguments(string[] args)
        {
            Dictionary<string, string> result = new Dictionary<string, string>(StringComparer.Ordinal);
            for (int index = 0; index < args.Length; index++)
            {
                string item = args[index];
                if (!item.StartsWith("--", StringComparison.Ordinal)) continue;
                string key = item.Substring(2);
                if (index + 1 >= args.Length || args[index + 1].StartsWith("--", StringComparison.Ordinal)) throw new InvalidOperationException("Missing value for --" + key + ".");
                result.Add(key, args[++index]);
            }
            return result;
        }

        private static string Required(Dictionary<string, string> arguments, string key)
        {
            string value;
            if (!arguments.TryGetValue(key, out value) || string.IsNullOrWhiteSpace(value)) throw new InvalidOperationException("Missing required --" + key + " argument.");
            return value;
        }

        private static int ParseInt(string value, string key)
        {
            int result;
            if (!int.TryParse(value, NumberStyles.None, CultureInfo.InvariantCulture, out result)) throw new InvalidOperationException("Invalid integer for --" + key + ".");
            return result;
        }

        private static void WriteJson(string path, object value)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(path));
            string json = JsonUtility.ToJson(value, true).Replace("\r\n", "\n").Replace("\r", "\n") + "\n";
            File.WriteAllText(path, json, new UTF8Encoding(false));
        }

        [Serializable]
        private sealed class PreflightMarker
        {
            public string schema;
            public string studyId;
            public string status;
            public string mode;
            public int unitCount;
            public int unitsWithEnabledRenderer;
            public int renderedFrameCount;
            public int structuralEventCount;
            public long gridRevision;
            public long visualRevision;
            public bool gridPlannerVisualRevisionMatch;
            public bool methodIdentitySuppressedInMarker;
            public bool m1ThroughM5SummaryProduced;
            public bool frameTimeOrFpsSummaryProduced;
            public bool rankingWinnerOrSuperiorityProduced;
            public bool formalObservationProduced;
            public bool formalPhaseAStarted;
        }

        [Serializable]
        private sealed class FailureMarker
        {
            public string schema;
            public string studyId;
            public string status;
            public string mode;
            public string exceptionType;
            public string message;
            public bool formalObservationProduced;
            public bool formalPhaseAStarted;
        }
    }
}
