using System;
using System.Globalization;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using DDM.Research.Gate14Re.V2;
using UnityEditor;
using UnityEditor.Build.Reporting;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.SceneManagement;

namespace DDM.Research.Editor
{
    public static class Gate14ReFormalBuildCommandV1
    {
        private const string SceneAssetPath = "Assets/_Scripts/Research/Gate14Re/v2/Gate14ReFormalRunnerV1.unity";
        private const string PrefabAssetPath = "Assets/Prefabs/NavMesh/NavMesh_PlayerUnit.prefab";
        private const string RelativeBuildDirectory = "Research/Verification/Gate14Re/formal-executor-implementation-attempt-001/standalone-build-attempt-003";

        public static void Build()
        {
            try
            {
                string projectRoot = Path.GetFullPath(Path.Combine(Application.dataPath, ".."));
                string buildDirectory = Path.Combine(projectRoot, RelativeBuildDirectory.Replace('/', Path.DirectorySeparatorChar));
                string executablePath = Path.Combine(buildDirectory, "Gate14ReFormalRunner.exe");
                string receiptPath = Path.Combine(buildDirectory, "build-receipt.v2.json");
                if (Directory.Exists(buildDirectory)) throw new InvalidOperationException("Refusing to overwrite formal runner build attempt: " + buildDirectory);
                Directory.CreateDirectory(buildDirectory);

                CreateAndSaveScene();
                BuildReport report = BuildPipeline.BuildPlayer(new BuildPlayerOptions
                {
                    scenes = new[] { SceneAssetPath },
                    locationPathName = executablePath,
                    target = BuildTarget.StandaloneWindows64,
                    options = BuildOptions.None
                });
                if (report.summary.result != BuildResult.Succeeded) throw new InvalidOperationException("Formal runner build failed: " + report.summary.result);
                if (!File.Exists(executablePath)) throw new FileNotFoundException("Formal runner executable was not produced.", executablePath);
                string assemblyPath = Path.Combine(buildDirectory, "Gate14ReFormalRunner_Data", "Managed", "Assembly-CSharp.dll");
                if (!File.Exists(assemblyPath)) throw new FileNotFoundException("Formal runner Assembly-CSharp.dll was not produced.", assemblyPath);
                string sceneSourceFullPath = Path.Combine(projectRoot, SceneAssetPath.Replace('/', Path.DirectorySeparatorChar));

                BuildReceipt receipt = new BuildReceipt
                {
                    schema = "gate14re-formal-runner-build-receipt-v2",
                    studyId = "Gate14Re",
                    status = "PASS",
                    buildTarget = BuildTarget.StandaloneWindows64.ToString(),
                    developmentBuild = false,
                    sceneAssetPath = SceneAssetPath,
                    unitVisualPrefabAssetPath = PrefabAssetPath,
                    executableRelativePath = Forward(Path.GetRelativePath(projectRoot, executablePath)),
                    executableBytes = new FileInfo(executablePath).Length,
                    executableSha256 = Sha256File(executablePath),
                    assemblyCSharpBytes = new FileInfo(assemblyPath).Length,
                    assemblyCSharpSha256 = Sha256File(assemblyPath),
                    sceneSourceBytes = new FileInfo(sceneSourceFullPath).Length,
                    sceneSourceSha256 = Sha256File(sceneSourceFullPath),
                    totalBuildBytes = checked((long)report.summary.totalSize),
                    formalAuthorizationEmbedded = false,
                    formalRootCreated = false,
                    formalObservationProduced = false,
                    formalPhaseAStarted = false
                };
                WriteJson(receiptPath, receipt);
                new FileInfo(receiptPath).IsReadOnly = true;
                Debug.Log("GATE14RE_FORMAL_RUNNER_BUILD_PASS " + receipt.executableSha256);
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
            if (prefab == null) throw new FileNotFoundException("Canonical unit visual prefab is missing.", PrefabAssetPath);
            Scene scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
            GameObject controllerObject = new GameObject("Gate14Re formal runner v1");
            Gate14ReFormalControllerV1 controller = controllerObject.AddComponent<Gate14ReFormalControllerV1>();
            controller.unitVisualPrefab = prefab;
            EditorSceneManager.MarkSceneDirty(scene);
            if (!EditorSceneManager.SaveScene(scene, SceneAssetPath, false)) throw new InvalidOperationException("Failed to save formal runner scene.");
            AssetDatabase.SaveAssets();
        }

        private static string Sha256File(string path)
        {
            using (FileStream stream = File.OpenRead(path))
            using (SHA256 sha = SHA256.Create())
            {
                byte[] digest = sha.ComputeHash(stream);
                StringBuilder builder = new StringBuilder(digest.Length * 2);
                for (int index = 0; index < digest.Length; index++) builder.Append(digest[index].ToString("x2", CultureInfo.InvariantCulture));
                return builder.ToString();
            }
        }

        private static string Forward(string value) { return value.Replace('\\', '/'); }

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
            public long assemblyCSharpBytes;
            public string assemblyCSharpSha256;
            public long sceneSourceBytes;
            public string sceneSourceSha256;
            public long totalBuildBytes;
            public bool formalAuthorizationEmbedded;
            public bool formalRootCreated;
            public bool formalObservationProduced;
            public bool formalPhaseAStarted;
        }
    }
}
