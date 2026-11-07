using UnityEngine;

namespace DDM.Research.Visualization
{
    [CreateAssetMenu(fileName = "Gate11RCampaignProfile", menuName = "DDM Research/Gate 11R Campaign Profile")]
    public sealed class Gate11RCampaignProfile : ScriptableObject
    {
        public string schemaId;
        public string campaignId;
        public string matrixId;
        public string executionDesignId;
        public string scenarioId;
        public string scenarioRelativePath;
        public string scenarioSha256;
        public string scenarioFingerprintSha256;
        public string sceneAssetPath;
        public string comparisonCohortId;
        public string[] eligibleAlgorithmIds = new string[0];
        public string[] williamsRows = new string[0];
        public int defaultBlockOrdinal;
        public bool visualizationOnly = true;
        public bool timingEvidenceAllowed;
    }
}
