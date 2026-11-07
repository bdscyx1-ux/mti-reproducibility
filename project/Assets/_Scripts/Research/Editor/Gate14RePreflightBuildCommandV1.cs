using System;
using System.Globalization;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using DDM.Research.Gate14Re.V1;
using UnityEditor;
using UnityEditor.Build.Reporting;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.SceneManagement;

namespace DDM.Research.Editor
{
    public static class Gate14RePreflightBuildCommandV1
    {
        private const string SceneAssetPath = "Assets/_Scripts/Research/Gate14Re/v1/Gate14RePreflightV1.unity";
        private const string PrefabAssetPath = "Assets/Prefabs/NavMesh/NavMesh_PlayerUnit.prefab";
        private const string RelativeBuildDirectory = "Research/Verification/Gate14Re/implementation-attempt-001/standalone-build-attempt-002";

        public static void Build()
        {
            try
            {
                string projectRoot = Path.GetFullPath(Path.Combine(Application.dataPath, ".."));
                string buildDirectory = Path.Combine(projectRoot, RelativeBuildDirectory.Replace('/', Path.DirectorySeparatorChar));
                string playerPath = Path.Combine(buildDirectory, "Gate14RePreflight.exe");
                string receiptPath = Path.Combine(buildDirectory, "build-receipt.v1.json");

                if (Directory.Exists(buildDirectory))
                    throw new InvalidOperationException("Standalone build attempt directory already exists; refusing to overwrite it: " + buildDirectory);

                Directory.CreateDirectory(buildDirectory);
                CreateAndSaveScene();

                BuildPlayerOptions options = new BuildPlayerOptions
                {
                    scenes = new[] { SceneAssetPath },
                    locationPathName = playerPath,
                    target = BuildTarget.StandaloneWindows64,
                    options = BuildOptions.None
                };

                BuildReport report = BuildPipeline.BuildPlayer(options);
                BuildSummary summary = report.summary;
                if (summary.result != BuildResult.Succeeded)
                    throw new InvalidOperationException("Gate 14Re preflight standalone build failed: " + summary.result);
                if (!File.Exists(playerPath))
                    throw new FileNotFoundException("Gate 14Re preflight executable was not produced.", playerPath);

                BuildReceipt receipt = new BuildReceipt
                {
                    schema = "gate14re-preflight-build-receipt-v1",
                    studyId = "Gate14Re",
                    status = "PASS",
                    buildTarget = BuildTarget.StandaloneWindows64.ToString(),
                    developmentBuild = false,
                    sceneAssetPath = SceneAssetPath,
                    unitVisualPrefabAssetPath = PrefabAssetPath,
                    executableRelativePath = ToForwardSlash(Path.GetRelativePath(projectRoot, playerPath)),
                    executableBytes = new FileInfo(playerPath).Length,
                    executableSha256 = Sha256File(playerPath),
                    totalBuildBytes = checked((long)summary.totalSize),
                    formalObservationProduced = false,
                    formalPhaseAStarted = false
                };
                WriteJson(receiptPath, receipt);
                Debug.Log("GATE14RE_PREFLIGHT_BUILD_PASS " + receipt.executableSha256);
                EditorApplication.Exit(0);
            }
            catch (Exception exception)
            {
                Debug.LogException(exception);
                EditorApplication.Exit(1);
            }
        }

        private static void CreateAndSaveScene()
        {
            GameObject prefab = AssetDatabase.LoadAssetAtPath<GameObject>(PrefabAssetPath);
            if (prefab == null)
                throw new FileNotFoundException("Canonical Gate 14Re unit visual prefab was not found.", PrefabAssetPath);

            string sceneDirectory = Path.GetDirectoryName(SceneAssetPath).Replace('\\', '/');
            if (!AssetDatabase.IsValidFolder(sceneDirectory))
                throw new DirectoryNotFoundException("Gate 14Re scene asset directory does not exist: " + sceneDirectory);

            Scene scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
            GameObject controllerObject = new GameObject("Gate14Re preflight controller v1");
            Gate14RePreflightControllerV1 controller = controllerObject.AddComponent<Gate14RePreflightControllerV1>();
            controller.unitVisualPrefab = prefab;
            EditorSceneManager.MarkSceneDirty(scene);
            if (!EditorSceneManager.SaveScene(scene, SceneAssetPath, false))
                throw new InvalidOperationException("Failed to save Gate 14Re preflight scene: " + SceneAssetPath);
            AssetDatabase.SaveAssets();
        }

        private static string Sha256File(string path)
        {
            using (FileStream stream = File.OpenRead(path))
            using (SHA256 sha = SHA256.Create())
            {
                byte[] digest = sha.ComputeHash(stream);
                StringBuilder builder = new StringBuilder(digest.Length * 2);
                for (int index = 0; index < digest.Length; index++)
                    builder.Append(digest[index].ToString("x2", CultureInfo.InvariantCulture));
                return builder.ToString();
            }
        }

        private static string ToForwardSlash(string value)
        {
            return value.Replace('\\', '/');
        }

        private static void WriteJson(string path, object value)
        {
            string json = JsonUtility.ToJson(value, true).Replace("\r\n", "\n").Replace("\r", "\n") + "\n";
            File.WriteAllText(path, json, new UTF8Encoding(false));
        }

        [Serializable]
        private sealed class BuildReceipt
        {
            public string schema;
            public string studyId;
            public string status;
            public string buildTarget;
            public bool developmentBuild;
            public string sceneAssetPath;
            public string unitVisualPrefabAssetPath;
            public string executableRelativePath;
            public long executableBytes;
            public string executableSha256;
            public long totalBuildBytes;
            public bool formalObservationProduced;
            public bool formalPhaseAStarted;
        }
    }
}
