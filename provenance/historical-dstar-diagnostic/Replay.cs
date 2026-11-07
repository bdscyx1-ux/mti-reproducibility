using System;
using System.IO;
using System.Linq;
using System.Collections;
using System.Collections.Generic;
using System.Reflection;
using System.Web.Script.Serialization;
using DDM.Research.Navigation;
using DDM.Research.Algorithms;
using DDM.Research.Grid;
using DDM.Research.Scenarios;
using DDM.Research.Gate14Re.V1;

public class Replay {
 static JavaScriptSerializer json=new JavaScriptSerializer{MaxJsonLength=100000000,RecursionLimit=200};
 static string root; static StreamWriter output;
 static void Emit(object x){output.WriteLine(json.Serialize(x));output.Flush();}
 public class Job {public string mode,path,id,sha; public int footprint,n;}
 class Visual:IGate14ReVisualGridSynchronizerV1 {public long VisualRevision{get;private set;} public void Initialize(IReadOnlyNavigationGrid g){VisualRevision=g.Version;} public void ApplyGridChange(IReadOnlyNavigationGrid g,NavigationChangeSet c){VisualRevision=g.Version;}}
 class Observed:INavigationPlanner {
  public INavigationPlanner Inner; public IReadOnlyNavigationGrid Grid; public string Id; public string Version; public int Queries,Failed,Illegal; public Dictionary<string,int> Counts=new Dictionary<string,int>();
  public string AlgorithmId{get{return Inner.AlgorithmId;}} public NavigationPlannerCapabilities Capabilities{get{return Inner.Capabilities;}} public long GridVersion{get{return Inner.GridVersion;}}
  NavigationPlannerInitialization init;
  public NavigationOperationMetrics Initialize(IReadOnlyNavigationGrid g,NavigationPlannerInitialization i){Grid=g;init=i;return Inner.Initialize(g,i);}
  public NavigationRepairResult ApplyChanges(NavigationChangeSet c,double b){return Inner.ApplyChanges(c,b);}
  public void Reset(){Inner.Reset();}
  public NavigationPlanResult Plan(NavigationPlanRequest q){var r=Inner.Plan(q);Queries++;string k=r.Status+"/"+r.FailureReason;if(!Counts.ContainsKey(k))Counts[k]=0;Counts[k]++;
   bool legal=r.Status!=NavigationPlanStatus.Succeeded||Legal(r.Path,q); if(!legal)Illegal++;
   if(r.Status==NavigationPlanStatus.Failed){Failed++;Emit(new{kind="failed_query",job=Id,version=Version,request=q,status=r.Status.ToString(),reason=r.FailureReason.ToString(),diagnostic=KeyState(q)});}
   return r;
  }
  bool Legal(IReadOnlyList<GridCoordinate> p,NavigationPlanRequest q){if(p.Count==0||!p[0].Equals(q.start)||!p[p.Count-1].Equals(q.goal))return false;for(int i=0;i<p.Count;i++){if(!Grid.IsWalkable(p[i]))return false;if(i==0)continue;int dx=Math.Abs(p[i].x-p[i-1].x),dy=Math.Abs(p[i].y-p[i-1].y);if(dx>1||dy>1||dx+dy==0)return false;if(init.connectivity==NavigationGridConnectivity.FourWay&&dx+dy!=1)return false;if(dx==1&&dy==1&&!init.allowDiagonalCornerCutting&&(!Grid.IsWalkable(new GridCoordinate(p[i].x,p[i-1].y))||!Grid.IsWalkable(new GridCoordinate(p[i-1].x,p[i].y))))return false;}return true;}
  object KeyState(NavigationPlanRequest q){try{var t=Inner.GetType();var flags=BindingFlags.Instance|BindingFlags.NonPublic|BindingFlags.Public;var states=(IDictionary)t.GetField("agentStates",flags).GetValue(Inner);var s=states[q.agentId];var st=s.GetType();var g=(double[])st.GetField("G",flags).GetValue(s);var rhs=(double[])st.GetField("Rhs",flags).GetValue(s);int index=q.start.y*Grid.Width+q.start.x;return new{startG=g[index].ToString("R"),startRhs=rhs[index].ToString("R"),consistent=Math.Abs(g[index]-rhs[index])<=1e-12};}catch(Exception e){return new{error=e.Message};}}
 }
 public static void Main(string[] args){root=args[0];var jobs=json.Deserialize<Job[]>(File.ReadAllText(args[1]));using(output=new StreamWriter(args[2])){foreach(var job in jobs){foreach(string ver in new[]{"historical","fixed"}){try{Run(job,ver);}catch(Exception e){Emit(new{kind="error",job=job.id,version=ver,error=e.ToString()});} }Console.WriteLine(job.id);}}}
 static void Run(Job j,string ver){var def=json.Deserialize<DeterministicScenarioDefinition>(File.ReadAllText(Path.Combine(root,j.path)));var obs=new Observed{Id=j.id,Version=ver,Inner=ver=="historical"?(INavigationPlanner)new DStarLitePlanner():new FixedDStarLitePlanner()};string run="diagnostic-"+j.id;
  if(j.mode=="movement"){
   var loaded=new LoadedDeterministicScenario(j.path,j.sha,def,def.Resolve());var prep=Gate14ReProtocolV1.Prepare(loaded,def.scenarioId,j.sha,j.id,j.footprint,j.n);var kernel=new Gate14ReMovementKernelV1(run,prep.Resolved,obs,new Visual());kernel.Release();
   while(kernel.Units.Any(u=>u.State==Gate14ReUnitTerminalStateV1.Active)&&kernel.CurrentTick<8998)kernel.AdvanceOneFixedTick();
   Emit(new{kind="summary",job=j.id,version=ver,mode=j.mode,queries=obs.Queries,statuses=obs.Counts,illegalSucceededPaths=obs.Illegal,terminal=kernel.Units.GroupBy(u=>u.State.ToString()).ToDictionary(g=>g.Key,g=>g.Count()),terminalAgents=kernel.Units.Where(u=>u.State!=Gate14ReUnitTerminalStateV1.Arrived).Select(u=>new{agent=u.AgentId,state=u.State.ToString()}).ToArray(),ticks=kernel.CurrentTick});
  }else{
   var s=def.Resolve();var grid=s.CreateGrid();obs.Initialize(grid,new NavigationPlannerInitialization{runId=run,goalSetId=s.GoalSetId,goals=s.Goals.ToArray(),connectivity=s.Connectivity,allowDiagonalCornerCutting=s.AllowDiagonalCornerCutting,budgetMilliseconds=s.InitializationBudgetMilliseconds});
   Action<string> query=(phase)=>{foreach(var a in s.Agents)obs.Plan(new NavigationPlanRequest{runId=run,requestId=phase,goalSetId=s.GoalSetId,agentId=a.AgentId,start=a.Start,goal=a.Goal,expectedGridVersion=grid.Version,budgetMilliseconds=s.DefaultPlanBudgetMilliseconds});};query("initial");
   foreach(var group in s.ScheduledChanges.GroupBy(e=>e.SimulationTick)){foreach(var e in group){var c=grid.ApplyChanges(e.EventId,grid.Version,e.Changes);var rr=obs.ApplyChanges(c,e.RepairBudgetMilliseconds);if(rr.Status!=NavigationPlanStatus.Succeeded)Emit(new{kind="repair",job=j.id,version=ver,eventId=e.EventId,status=rr.Status.ToString(),reason=rr.FailureReason.ToString()});}query("tick-"+group.Key);}
   Emit(new{kind="summary",job=j.id,version=ver,mode=j.mode,queries=obs.Queries,statuses=obs.Counts,illegalSucceededPaths=obs.Illegal});
  }
 }
}
