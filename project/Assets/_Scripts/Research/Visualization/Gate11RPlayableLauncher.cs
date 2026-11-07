using System;
using DDM.Research.Scenarios;
using UnityEngine;
#if UNITY_EDITOR
using UnityEditor;
using UnityEditor.SceneManagement;
#endif

namespace DDM.Research.Visualization
{
    public static class Gate11RPlayableSelection
    {
        public static bool HasSelection { get; private set; }
        public static string ScenarioId { get; private set; }
        public static string CampaignId { get; private set; }
        public static string AlgorithmId { get; private set; }
        public static int BlockOrdinal { get; private set; }

        public static void Set(string scenarioId, string campaignId, string algorithmId, int blockOrdinal)
        {
            ScenarioId = scenarioId ?? string.Empty;
            CampaignId = campaignId ?? string.Empty;
            AlgorithmId = algorithmId ?? string.Empty;
            BlockOrdinal = Math.Max(0, blockOrdinal);
            HasSelection = true;
        }

        public static void Clear()
        {
            HasSelection = false;
            ScenarioId = CampaignId = AlgorithmId = string.Empty;
            BlockOrdinal = 0;
        }
    }

    /// <summary>Editor-oriented launcher for all Gate 11R visualization cells.</summary>
    public sealed class Gate11RPlayableLauncher : MonoBehaviour
    {
        public string schemaId;
        public string matrixId;
        public string playableBundleId;
        public string[] presetIds = new string[0];
        public string[] scenarioIds = new string[0];
        public string[] campaignIds = new string[0];
        public string[] algorithmIds = new string[0];
        public string[] sceneAssetPaths = new string[0];
        public string watermark = Gate11RFormalScenarioMatrixGenerator.VisualizationWatermark;
        public bool visualizationOnly = true;
        public bool timingEvidenceAllowed;

        private int selectedIndex;
        private int blockOrdinal;
        private Vector2 scroll;

        public void Configure(string[] configuredPresetIds, string[] configuredScenarioIds, string[] configuredCampaignIds, string[] configuredAlgorithmIds, string[] configuredScenePaths)
        {
            schemaId = "gate11r-playable-launcher-v1";
            matrixId = Gate11RFormalScenarioMatrixGenerator.MatrixId;
            playableBundleId = Gate11RFormalScenarioMatrixGenerator.PlayableBundleId;
            presetIds = configuredPresetIds ?? new string[0];
            scenarioIds = configuredScenarioIds ?? new string[0];
            campaignIds = configuredCampaignIds ?? new string[0];
            algorithmIds = configuredAlgorithmIds ?? new string[0];
            sceneAssetPaths = configuredScenePaths ?? new string[0];
            watermark = Gate11RFormalScenarioMatrixGenerator.VisualizationWatermark;
            visualizationOnly = true;
            timingEvidenceAllowed = false;
        }

        private void OnGUI()
        {
            GUI.depth = -100;
            GUILayout.BeginArea(new Rect(20f, 20f, Mathf.Max(500f, Screen.width - 40f), Mathf.Max(300f, Screen.height - 40f)), GUI.skin.box);
            GUILayout.Label("Gate 11R Playable experiment launcher — 53 scenes / 74 campaign profiles / 212 algorithm presets");
            GUILayout.Label(watermark);
            if (!IsShapeValid())
            {
                GUILayout.Label("Launcher catalog arrays are invalid. Run the Gate 11R verifier.");
                GUILayout.EndArea();
                return;
            }
            GUILayout.BeginHorizontal();
            if (GUILayout.Button("Previous", GUILayout.Width(100f))) selectedIndex = (selectedIndex + presetIds.Length - 1) % presetIds.Length;
            if (GUILayout.Button("Next", GUILayout.Width(100f))) selectedIndex = (selectedIndex + 1) % presetIds.Length;
            GUILayout.Label("Preset " + (selectedIndex + 1) + " / " + presetIds.Length);
            GUILayout.EndHorizontal();
            blockOrdinal = Mathf.RoundToInt(GUILayout.HorizontalSlider(blockOrdinal, 0, 31));
            GUILayout.Label("Visualization Williams block ordinal: " + blockOrdinal);
            scroll = GUILayout.BeginScrollView(scroll, GUILayout.Height(Mathf.Max(140f, Screen.height - 220f)));
            GUILayout.Label("Preset: " + presetIds[selectedIndex]);
            GUILayout.Label("Scenario: " + scenarioIds[selectedIndex]);
            GUILayout.Label("Campaign: " + campaignIds[selectedIndex]);
            GUILayout.Label("Algorithm: " + algorithmIds[selectedIndex]);
            GUILayout.Label("Scene: " + sceneAssetPaths[selectedIndex]);
            GUILayout.Label("Use Previous/Next to select any of the 212 eligible cells. This launcher and every scene are visualization-only; no timing sample is collected.");
            GUILayout.EndScrollView();
            if (GUILayout.Button("Open selected Playable scene", GUILayout.Height(40f))) OpenSelected();
            GUILayout.EndArea();
        }

        public bool IsShapeValid()
        {
            int length = presetIds == null ? 0 : presetIds.Length;
            return length == Gate11RFormalScenarioMatrixGenerator.ExpectedPresetCount &&
                   scenarioIds != null && scenarioIds.Length == length &&
                   campaignIds != null && campaignIds.Length == length &&
                   algorithmIds != null && algorithmIds.Length == length &&
                   sceneAssetPaths != null && sceneAssetPaths.Length == length;
        }

        public void OpenSelected()
        {
            if (!IsShapeValid()) throw new InvalidOperationException("Gate 11R launcher catalog arrays are invalid.");
            selectedIndex = Mathf.Clamp(selectedIndex, 0, presetIds.Length - 1);
            Gate11RPlayableSelection.Set(scenarioIds[selectedIndex], campaignIds[selectedIndex], algorithmIds[selectedIndex], blockOrdinal);
#if UNITY_EDITOR
            string scenePath = sceneAssetPaths[selectedIndex];
            if (EditorApplication.isPlaying)
            {
                EditorApplication.isPlaying = false;
                EditorApplication.delayCall += delegate { EditorSceneManager.OpenScene(scenePath, OpenSceneMode.Single); };
            }
            else EditorSceneManager.OpenScene(scenePath, OpenSceneMode.Single);
#else
            Debug.LogError("Gate 11R launcher scene switching is supported in the Unity Editor. Open: " + sceneAssetPaths[selectedIndex]);
#endif
        }
    }
}
