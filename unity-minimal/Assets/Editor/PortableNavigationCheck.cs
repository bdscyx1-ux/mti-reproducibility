using System;
using System.IO;
using System.Collections.Generic;
using DDM.Research.Navigation;
using DDM.Research.Algorithms;
using UnityEngine;
using UnityEditor;

// Independent, small functional check. This does not collect manuscript timings.
public static class PortableNavigationCheck
{
    sealed class Grid : IReadOnlyNavigationGrid
    {
        public int Width { get { return 7; } }
        public int Height { get { return 5; } }
        public long Version { get; private set; }
        readonly bool[] walkable = new bool[35];
        readonly float[] costs = new float[35];
        public Grid() { for (int i=0;i<35;i++) { walkable[i]=true;costs[i]=1f+(i%3)*0.25f; } }
        int Index(GridCoordinate p) { return p.y*Width+p.x; }
        public bool Contains(GridCoordinate p) { return p.x>=0 && p.y>=0 && p.x<Width && p.y<Height; }
        public bool IsWalkable(GridCoordinate p) { return Contains(p) && walkable[Index(p)]; }
        public float GetTraversalCost(GridCoordinate p) { return costs[Index(p)]; }
        public NavigationChangeSet Change(int stage)
        {
            var changes = new List<NavigationGridChange>();
            if (stage==1 || stage==2 || stage==3)
                for(int y=0;y<Height;y++) changes.Add(new NavigationGridChange { coordinate=new GridCoordinate(3,y), isWalkable=(stage==1 && y==4)||(stage==3 && y==2), traversalCost=costs[y*Width+3] });
            else changes.Add(new NavigationGridChange { coordinate=new GridCoordinate(3,2),isWalkable=true,traversalCost=10f });
            long before=Version;
            foreach(var c in changes) { walkable[Index(c.coordinate)]=c.isWalkable;costs[Index(c.coordinate)]=c.traversalCost; }
            Version++;
            return new NavigationChangeSet { changeSetId="change-"+stage,previousGridVersion=before,newGridVersion=Version,changes=changes.ToArray() };
        }
    }
    [Serializable] public class Check { public string algorithm,connectivity,stage,status; public int agent;public double expectedCost,actualCost; }
    [Serializable] public class Receipt { public string status,unityVersion,scope,error;public int checkCount; public List<Check> checks=new List<Check>(); }
    static bool Legal(Grid g,GridCoordinate a,GridCoordinate b,bool eight)
    {
        int dx=Math.Abs(a.x-b.x),dy=Math.Abs(a.y-b.y);
        if (!g.IsWalkable(b)||dx>1||dy>1||dx+dy==0||(!eight&&dx+dy!=1)) return false;
        return dx+dy!=2 || (g.IsWalkable(new GridCoordinate(a.x,b.y))&&g.IsWalkable(new GridCoordinate(b.x,a.y)));
    }
    static double Cost(Grid g,GridCoordinate a,GridCoordinate b) { return g.GetTraversalCost(b)*(a.x!=b.x&&a.y!=b.y?Math.Sqrt(2):1); }
    static double Oracle(Grid g,GridCoordinate start,GridCoordinate goal,bool eight)
    {
        var d=new double[35];var used=new bool[35];for(int i=0;i<35;i++)d[i]=double.PositiveInfinity;d[start.y*7+start.x]=0;
        for(int step=0;step<35;step++)
        {
            int best=-1;for(int i=0;i<35;i++)if(!used[i]&&(best<0||d[i]<d[best]))best=i;
            if(best<0||double.IsPositiveInfinity(d[best]))break;used[best]=true;var a=new GridCoordinate(best%7,best/7);
            if(a.Equals(goal))return d[best];
            for(int y=-1;y<=1;y++)for(int x=-1;x<=1;x++)
            { var b=new GridCoordinate(a.x+x,a.y+y);if(!Legal(g,a,b,eight))continue;int j=b.y*7+b.x;d[j]=Math.Min(d[j],d[best]+Cost(g,a,b)); }
        }
        return double.PositiveInfinity;
    }
    public static void Run()
    {
        string output=null;var receipt=new Receipt { status="FAIL",unityVersion=Application.unityVersion,scope="Six frozen backends; two connectivities; weighted grid; block, disconnect, reconnect and cost updates. Functional check only." };
        try
        {
            var args=Environment.GetCommandLineArgs();int n=Array.IndexOf(args,"-portableResult");
            if(n<0||n+1>=args.Length)throw new Exception("Missing -portableResult");output=Path.GetFullPath(args[n+1]);
            if(File.Exists(output))throw new Exception("Result already exists");
            Func<INavigationPlanner>[] constructors={ ()=>new AStarRepeatedPlanner(),()=>new BidirectionalAStarRepeatedPlanner(),()=>new DStarLitePlanner(),()=>new LifelongPlanningAStarPlanner(),()=>new CorrectedFullRecomputeFlowFieldPlanner(),()=>new IncrementalDynamicFlowFieldPlanner() };
            foreach(var create in constructors)for(int mode=0;mode<2;mode++)
            {
                bool eight=mode==1;var grid=new Grid();var planner=create();var goal=new GridCoordinate(6,2);
                planner.Initialize(grid,new NavigationPlannerInitialization {runId="portable",goalSetId="goal",goals=new[]{goal},connectivity=eight?NavigationGridConnectivity.EightWay:NavigationGridConnectivity.FourWay,allowDiagonalCornerCutting=false,budgetMilliseconds=10000});
                for(int stage=0;stage<5;stage++)
                {
                    if(stage>0)planner.ApplyChanges(grid.Change(stage),10000);
                    for(int agent=0;agent<2;agent++)
                    {
                        var start=new GridCoordinate(0,agent*4);double expected=Oracle(grid,start,goal,eight);
                        var result=planner.Plan(new NavigationPlanRequest {runId="portable",requestId=stage+"-"+agent,goalSetId="goal",agentId=agent,start=start,goal=goal,expectedGridVersion=grid.Version,budgetMilliseconds=10000});
                        double actual=0;
                        if(double.IsPositiveInfinity(expected)) { if(result.Status!=NavigationPlanStatus.NoPath)throw new Exception(planner.AlgorithmId+" expected NoPath"); }
                        else
                        {
                            if(result.Status!=NavigationPlanStatus.Succeeded||result.Path.Count<2||!result.Path[0].Equals(start)||!result.Path[result.Path.Count-1].Equals(goal))throw new Exception(planner.AlgorithmId+" invalid endpoint/status");
                            for(int i=1;i<result.Path.Count;i++) { if(!Legal(grid,result.Path[i-1],result.Path[i],eight))throw new Exception("Illegal edge");actual+=Cost(grid,result.Path[i-1],result.Path[i]); }
                            if(Math.Abs(actual-expected)>1e-8*Math.Max(1,expected))throw new Exception(planner.AlgorithmId+" oracle cost mismatch");
                        }
                        if(result.GridVersion!=grid.Version)throw new Exception("Stale result version");
                        receipt.checks.Add(new Check {algorithm=planner.AlgorithmId,connectivity=eight?"eight-strict":"four",stage=stage.ToString(),agent=agent,status=result.Status.ToString(),expectedCost=double.IsInfinity(expected)?-1:expected,actualCost=double.IsInfinity(expected)?-1:actual});
                    }
                }
                planner.Reset();
            }
            receipt.checkCount=receipt.checks.Count;if(receipt.checkCount!=120)throw new Exception("Wrong check count");receipt.status="PASS";
        }
        catch(Exception e) { receipt.error=e.ToString();Debug.LogException(e); }
        if(output!=null&&!File.Exists(output)) { Directory.CreateDirectory(Path.GetDirectoryName(output));File.WriteAllText(output,JsonUtility.ToJson(receipt,true)); }
        EditorApplication.Exit(receipt.status=="PASS"?0:1);
    }
}
