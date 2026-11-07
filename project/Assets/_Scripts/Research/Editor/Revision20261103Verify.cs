using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using DDM.Research.Navigation;
using DDM.Research.Algorithms;
using DDM.Research.Scenarios;
using UnityEngine;
using UnityEditor;
namespace DDM.Research.Editor {
 public static class Revision20261103Verify {
  [Serializable] class Cases { public Revision20261103Planning.Plan[] items; }
  [Serializable] class Row { public string scenario,algorithm;public int queries,success,noPath,mismatches; public string[] errors; }
  [Serializable] class Report { public bool passed;public string reference="Independent reverse Dijkstra using SortedSet; directed entry costs, connectivity and corner policy";public Row[] rows; }
  static Dictionary<string,double[]> cache=new Dictionary<string,double[]>();
  static double[] Dist(IReadOnlyNavigationGrid g,NavigationPlannerInitialization init,GridCoordinate goal){
   string key=g.Version+":"+goal.x+":"+goal.y;
   double[] d;if(cache.TryGetValue(key,out d))return d;
   d=Enumerable.Repeat(double.PositiveInfinity,g.Width*g.Height).ToArray();cache[key]=d;
   if(!g.Contains(goal)||!g.IsWalkable(goal))return d;
   var queue=new SortedSet<Tuple<double,int>>();int gi=goal.y*g.Width+goal.x;d[gi]=0;queue.Add(Tuple.Create(0d,gi));
   while(queue.Count>0){var cur=queue.Min;queue.Remove(cur);if(cur.Item1!=d[cur.Item2])continue;
    var v=new GridCoordinate(cur.Item2%g.Width,cur.Item2/g.Width);
    for(int dy=-1;dy<=1;dy++)for(int dx=-1;dx<=1;dx++){
     if(dx==0&&dy==0)continue;if(init.connectivity==NavigationGridConnectivity.FourWay&&Math.Abs(dx)+Math.Abs(dy)!=1)continue;
     var u=new GridCoordinate(v.x+dx,v.y+dy);if(!g.Contains(u)||!g.IsWalkable(u))continue;
     if(dx!=0&&dy!=0&&!init.allowDiagonalCornerCutting&&(!g.IsWalkable(new GridCoordinate(u.x,v.y))||!g.IsWalkable(new GridCoordinate(v.x,u.y))))continue;
     int ui=u.y*g.Width+u.x;double alt=cur.Item1+g.GetTraversalCost(v)*(dx!=0&&dy!=0?Math.Sqrt(2):1);
     if(alt<d[ui]){d[ui]=alt;queue.Add(Tuple.Create(alt,ui));}
    }
   }return d;
  }
  static Row Verify(Revision20261103Planning.Plan item,string id){
   var s=DeterministicScenarioJson.LoadFromFile(item.scenarioPath).Resolved;var g=s.CreateGrid();
   INavigationPlanner p=id=="A*-R"?(INavigationPlanner)new AStarRepeatedPlanner():id=="D*L"?new DStarLitePlanner():id=="C-FF"?new CorrectedFullRecomputeFlowFieldPlanner():(INavigationPlanner)new IncrementalDynamicFlowFieldPlanner();
   var init=new NavigationPlannerInitialization{runId="verify",goalSetId=s.GoalSetId,goals=s.Goals.ToArray(),connectivity=s.Connectivity,allowDiagonalCornerCutting=s.AllowDiagonalCornerCutting,budgetMilliseconds=s.InitializationBudgetMilliseconds};p.Initialize(g,init);
   var row=new Row{scenario=item.scenarioId,algorithm=id};var errors=new List<string>();
   Action query=()=>{foreach(var a in s.Agents){
    var q=new NavigationPlanRequest{runId="verify",requestId="oracle",goalSetId=s.GoalSetId,agentId=a.AgentId,start=a.Start,goal=a.Goal,expectedGridVersion=g.Version,budgetMilliseconds=s.DefaultPlanBudgetMilliseconds};
    var r=p.Plan(q);row.queries++;var d=Dist(g,init,a.Goal);double expected=g.IsWalkable(a.Start)?d[a.Start.y*g.Width+a.Start.x]:double.PositiveInfinity;
    bool okay=true;
    if(r.Status==NavigationPlanStatus.Succeeded){row.success++;var path=r.Path;double cost=0;okay=path.Count>0&&path[0].Equals(a.Start)&&path[path.Count-1].Equals(a.Goal)&&!double.IsInfinity(expected);
     for(int n=0;n<path.Count;n++){if(!g.Contains(path[n])||!g.IsWalkable(path[n])){okay=false;break;}if(n==0)continue;
      var u=path[n-1];var v=path[n];int dx=Math.Abs(u.x-v.x),dy=Math.Abs(u.y-v.y);
      if(dx>1||dy>1||dx+dy==0||(init.connectivity==NavigationGridConnectivity.FourWay&&dx+dy!=1)){okay=false;break;}
      if(dx==1&&dy==1&&!init.allowDiagonalCornerCutting&&(!g.IsWalkable(new GridCoordinate(u.x,v.y))||!g.IsWalkable(new GridCoordinate(v.x,u.y)))){okay=false;break;}
      cost+=g.GetTraversalCost(v)*(dx==1&&dy==1?Math.Sqrt(2):1);
     }
     okay=okay&&Math.Abs(cost-expected)<=1e-7*Math.Max(1,Math.Abs(expected));
    }else if(r.Status==NavigationPlanStatus.NoPath){row.noPath++;okay=double.IsInfinity(expected);}else okay=false;
    if(!okay){row.mismatches++;if(errors.Count<12)errors.Add("agent="+a.AgentId+" version="+g.Version+" status="+r.Status+" reason="+r.FailureReason+" oracle="+expected);}
   }};query();foreach(var group in s.ScheduledChanges.GroupBy(e=>e.SimulationTick)){foreach(var e in group){var change=g.ApplyChanges(e.EventId,g.Version,e.Changes);p.ApplyChanges(change,e.RepairBudgetMilliseconds);}query();}p.Reset();row.errors=errors.ToArray();return row;
  }
  public static void Run(){
   string output="C:/Users/bdscy/DDM_Revision_20261103/A-oracle-verification.json";
   try{var cases=JsonUtility.FromJson<Cases>(File.ReadAllText("C:/Users/bdscy/DDM_Revision_20261103/A-verification-cases.json"));var rows=new List<Row>();
    foreach(var c in cases.items){cache.Clear();foreach(string id in new[]{"A*-R","D*L","C-FF","IDFF"})rows.Add(Verify(c,id));UnityEngine.Debug.Log("VERIFIED_CASE "+c.scenarioId);}
    var result=new Report{rows=rows.ToArray(),passed=rows.All(r=>r.mismatches==0)};
    using(var f=new FileStream(output,FileMode.CreateNew))using(var w=new StreamWriter(f))w.Write(JsonUtility.ToJson(result,true));EditorApplication.Exit(result.passed?0:2);
   }catch(Exception e){UnityEngine.Debug.LogException(e);EditorApplication.Exit(1);}
  }
 }
}
