using UnityEngine;

namespace DDM.Research.Visualization
{
    [CreateAssetMenu(fileName = "Gate11RAlgorithmPreset", menuName = "DDM Research/Gate 11R Algorithm Preset")]
    public sealed class Gate11RAlgorithmPreset : ScriptableObject
    {
        public string schemaId;
        public string presetId;
        public string matrixEntryId;
        public string campaignId;
        public string campaignProfileAssetPath;
        public string scenarioId;
        public string scenarioRelativePath;
        public string scenarioSha256;
        public string sceneAssetPath;
        public string comparisonCohortId;
        public string algorithmId;
        public string directionGlyphId;
        public string captureLayoutId;
        public string watermark;
        public bool showGrid = true;
        public bool showCosts = true;
        public bool showAgents = true;
        public bool showGoals = true;
        public bool showPath = true;
        public bool showIntegration = true;
        public bool showDirections = true;
        public bool showExpandedAndRepairedMetrics = true;
        public bool visualizationOnly = true;
        public bool timingEvidenceAllowed;
    }
}
