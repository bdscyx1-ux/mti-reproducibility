using System;
using System.Globalization;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using DDM.Research.Gate14ReTB.V1;
using UnityEditor;
using UnityEditor.Build.Reporting;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.SceneManagement;

namespace DDM.Research.Editor
{
    public static class Gate14ReTBFormalBuildCommandV1
    {
        private const string SceneAssetPath = "Assets/_Scripts/Research/Gate14ReTB/v1/Gate14ReTBFormalRunnerV1.unity";
        private const string PrefabAssetPath = "Assets/Prefabs/NavMesh/NavMesh_PlayerUnit.prefab";
        private const string RelativeBuildDirectory = "Research/Verification/Gate14Re-TB/precollection-implementation-attempt-001/standalone-build-attempt-001";

        public static void Build()
        {
            try
            {
                string root = Path.GetFullPath(Path.Combine(Application.dataPath, ".."));
                string directory = Path.Combine(root, RelativeBuildDirectory.Replace('/', Path.DirectorySeparatorChar));
                if (Directory.Exists(directory)) throw new InvalidOperationException("Refusing to overwrite standalone build attempt.");
                Directory.CreateDirectory(directory);
                string executable = Path.Combine(directory, "Gate14ReTBFormalRunner.exe");
                CreateAndSaveScene();
                BuildReport report = BuildPipeline.BuildPlayer(new BuildPlayerOptions { scenes = new[] { SceneAssetPath }, locationPathName = executable, target = BuildTarget.StandaloneWindows64, options = BuildOptions.None });
                if (report.summary.result != BuildResult.Succeeded) throw new InvalidOperationException("Standalone build failed: " + report.summary.result);
                string assembly = Path.Combine(directory, "Gate14ReTBFormalRunner_Data", "Managed", "Assembly-CSharp.dll");
                if (!File.Exists(executable) || !File.Exists(assembly)) throw new FileNotFoundException("Standalone executable or managed assembly is missing.");
                string scene = Path.Combine(root, SceneAssetPath.Replace('/', Path.DirectorySeparatorChar));
                BuildReceipt receipt = new BuildReceipt
                {
                    schema = "gate14re-tb-standalone-build-receipt-v1",
                    studyId = "Gate14Re-TB",
                    status = "PASS_NON_EXECUTING",
                    buildTarget = BuildTarget.StandaloneWindows64.ToString(),
                    developmentBuild = false,
                    sceneAssetPath = SceneAssetPath,
                    unitVisualPrefabAssetPath = PrefabAssetPath,
                    executableRelativePath = Forward(Path.GetRelativePath(root, executable)),
                    executableBytes = new FileInfo(executable).Length,
                    executableSha256 = Sha256File(executable),
                    assemblyCSharpBytes = new FileInfo(assembly).Length,
                    assemblyCSharpSha256 = Sha256File(assembly),
                    sceneSourceBytes = new FileInfo(scene).Length,
                    sceneSourceSha256 = Sha256File(scene),
                    totalBuildBytes = checked((long)report.summary.totalSize),
                    authorizationEmbedded = false,
                    productionIdentityEmbeddedInScene = false,
                    measuredRootCreated = false,
                    formalObservationProduced = false,
                    collectionStarted = false
                };
                string receiptPath = Path.Combine(directory, "build-receipt.v1.json");
                File.WriteAllText(receiptPath, JsonUtility.ToJson(receipt, true).Replace("\r\n", "\n").Replace("\r", "\n") + "\n", new UTF8Encoding(false));
                new FileInfo(receiptPath).IsReadOnly = true;
                Debug.Log("GATE14RE_TB_STANDALONE_BUILD_PASS " + receipt.executableSha256);
                EditorApplication.Exit(0);
            }
            catch (Exception exception) { Debug.LogException(exception); EditorApplication.Exit(1); }
        }

        private static void CreateAndSaveScene()
        {
            GameObject prefab = AssetDatabase.LoadAssetAtPath<GameObject>(PrefabAssetPath);
            if (prefab == null) throw new FileNotFoundException("Canonical unit visual prefab is missing.", PrefabAssetPath);
            Scene scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
            GameObject controllerObject = new GameObject("Gate14Re-TB anonymous formal runner v1");
            Gate14ReTBFormalControllerV1 controller = controllerObject.AddComponent<Gate14ReTBFormalControllerV1>();
            controller.unitVisualPrefab = prefab;
            EditorSceneManager.MarkSceneDirty(scene);
            if (!EditorSceneManager.SaveScene(scene, SceneAssetPath, false)) throw new InvalidOperationException("Failed to save Gate14Re-TB runner scene.");
            AssetDatabase.SaveAssets();
        }

        private static string Sha256File(string path) { using (FileStream stream = File.OpenRead(path)) using (SHA256 sha = SHA256.Create()) { byte[] digest = sha.ComputeHash(stream); StringBuilder builder = new StringBuilder(digest.Length * 2); for (int index = 0; index < digest.Length; index++) builder.Append(digest[index].ToString("x2", CultureInfo.InvariantCulture)); return builder.ToString(); } }
        private static string Forward(string path) { return path.Replace('\\', '/'); }

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
            public long assemblyCSharpBytes;
            public string assemblyCSharpSha256;
            public long sceneSourceBytes;
            public string sceneSourceSha256;
            public long totalBuildBytes;
            public bool authorizationEmbedded;
            public bool productionIdentityEmbeddedInScene;
            public bool measuredRootCreated;
            public bool formalObservationProduced;
            public bool collectionStarted;
        }
    }
}
