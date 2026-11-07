using System;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.CompilerServices;
using System.Security.Cryptography;
using System.Diagnostics;
using DDM.Research.Algorithms;
using DDM.Research.Experiments;
using DDM.Research.Logging;
using DDM.Research.Navigation;
using DDM.Research.Scenarios;
using UnityEditor;
using UnityEngine;

namespace DDM.Research.Editor {
 public static class Revision20261103Planning {
  [Serializable] public class Binding { public string path,sha256; }
  [Serializable] public class Plan { public string studyId,scenarioId,scenarioPath,scenarioSha256,outputRoot; public int blockIndex; public string[] algorithms; public Binding[] bindings; }
  [Serializable] public class BlockResult { public string studyId,scenarioId,planSha256,startedAtUtc,completedAtUtc,unityVersion; public int blockIndex,processId; public bool completed; public PlanningWorkloadResult[] samples; }
  [Serializable] public class Failure { public string status="FAILED",exception; }
  static string Arg(string k) { var a=Environment.GetCommandLineArgs(); int i=Array.IndexOf(a,k); if(i<0||i+1>=a.Length)throw new Exception("Missing "+k);return a[i+1]; }
  static string Hash(string p) { using(var f=File.OpenRead(p))using(var s=SHA256.Create())return BitConverter.ToString(s.ComputeHash(f)).Replace("-","").ToLowerInvariant(); }
  static void Write(string p,object o) { using(var f=new FileStream(p,FileMode.CreateNew))using(var w=new StreamWriter(f,new System.Text.UTF8Encoding(false)))w.Write(JsonUtility.ToJson(o,true)); }
  static void Collect(){ GC.Collect();GC.WaitForPendingFinalizers();GC.Collect(); }
  public static void Run() {
   string output=null;
   try {
    string pp=Arg("-revisionPlan"), expected=Arg("-revisionPlanSha256");
    if(Hash(pp)!=expected)throw new Exception("Plan hash mismatch");
    var p=JsonUtility.FromJson<Plan>(File.ReadAllText(pp));
    if(p.studyId!="DDM-Revision-20261103-A"||p.blockIndex<1||p.blockIndex>48)throw new Exception("Invalid study/block");
    string[] ids={"A*-R","D*L","C-FF","IDFF"}; int[] baseOrder={0,1,3,2};
    var order=baseOrder.Select(i=>ids[(i+(p.blockIndex-1)%4)%4]).ToArray();
    if(!order.SequenceEqual(p.algorithms))throw new Exception("Williams order mismatch");
    foreach(var b in p.bindings)if(Hash(b.path)!=b.sha256)throw new Exception("Source changed: "+b.path);
    if(Hash(p.scenarioPath)!=p.scenarioSha256)throw new Exception("Scenario changed");
    output=Path.GetFullPath(Arg("-revisionOutput"));
    if(!output.StartsWith(Path.GetFullPath(p.outputRoot).TrimEnd('\\','/')+Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase))throw new Exception("Output outside study root");
    if(Directory.Exists(output))throw new Exception("Output already exists"); Directory.CreateDirectory(output);
    var result=new BlockResult{studyId=p.studyId,scenarioId=p.scenarioId,blockIndex=p.blockIndex,planSha256=expected,startedAtUtc=DateTime.UtcNow.ToString("o"),unityVersion=Application.unityVersion,processId=Process.GetCurrentProcess().Id,samples=new PlanningWorkloadResult[4]};
    for(int i=0;i<4;i++){
     Collect(); result.samples[i]=Sample(p,p.algorithms[i],Path.Combine(output,"p"+(i+1)),p.scenarioId+"-b"+p.blockIndex+"-p"+(i+1));Collect();
    }
    result.completedAtUtc=DateTime.UtcNow.ToString("o");result.completed=true;Write(Path.Combine(output,"block-result.json"),result);
    EditorApplication.Exit(0);
   }catch(Exception e){UnityEngine.Debug.LogException(e);if(output!=null&&Directory.Exists(output)&&!File.Exists(Path.Combine(output,"failure.json")))Write(Path.Combine(output,"failure.json"),new Failure{exception=e.ToString()});EditorApplication.Exit(1);}
  }
  [MethodImpl(MethodImplOptions.NoInlining)] static PlanningWorkloadResult Sample(Plan p,string id,string dir,string runId){
   Directory.CreateDirectory(dir);
   INavigationPlanner planner=id=="A*-R"?(INavigationPlanner)new AStarRepeatedPlanner():id=="D*L"?new DStarLitePlanner():id=="C-FF"?new CorrectedFullRecomputeFlowFieldPlanner():(INavigationPlanner)new IncrementalDynamicFlowFieldPlanner();
   string root=Directory.GetParent(Application.dataPath).FullName;
   var method=typeof(ResearchPlanningBatchCommand).GetMethod("BuildProvenance",BindingFlags.NonPublic|BindingFlags.Static);
   var provenance=(PlanningRunProvenance)method.Invoke(null,new object[]{root,id});
   var loaded=DeterministicScenarioJson.LoadFromFile(p.scenarioPath);
   PlanningWorkloadResult r;
   using(var log=new JsonlExperimentLogger(Path.Combine(dir,"operations.jsonl"),ExperimentLogFileMode.CreateNew)){
    r=DeterministicPlanningWorkloadRunner.Run(runId,loaded.Definition,planner,log,provenance);log.Flush(TimeSpan.FromSeconds(30));
    if(log.EnqueuedCount!=log.WrittenCount)throw new Exception("Incomplete operation log");
   }
   if(!r.completed||r.scenarioId!=p.scenarioId)throw new Exception("Incomplete/wrong workload");
   Write(Path.Combine(dir,"workload-result.json"),r);planner.Reset();return r;
  }
 }
}
