"""Check selected published supplemental results without Unity or original drive paths."""
from pathlib import Path
import argparse,csv,collections,hashlib,json,math,statistics,zipfile
ROOT=Path(__file__).resolve().parents[1]
from repository_layout import repository_path
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--archives',type=Path,required=True);args=ap.parse_args()
 sup=repository_path('supplement-20261103');idx={};handles={};read_count=0
 for label in ['supplement-A','supplement-B','supplement-plans']:
  with (args.archives/(label+'.files.csv')).open(encoding='utf-8',newline='') as f:
   for r in csv.DictReader(f):idx[r['path']]=r
 def load_local(p):return json.loads(p.read_text(encoding='utf-8-sig'))
 def member_path(value):
  s=str(value).replace('\\','/');marker='/DDM_Revision_20261103/'
  return 'supplement-20261103/'+s.split(marker,1)[1] if marker in s else s
 def raw(path):
  nonlocal read_count
  name=member_path(path);r=idx[name];archive=r['archive']
  if archive not in handles:handles[archive]=zipfile.ZipFile(args.archives/archive)
  data=handles[archive].read(name);assert hashlib.sha256(data).hexdigest()==r['sha256'],name
  read_count+=1;return json.loads(data),hashlib.sha256(data).hexdigest()
 def close(a,b):assert math.isclose(a,b,rel_tol=1e-10,abs_tol=1e-13),(a,b)
 try:
  A=load_local(repository_path('supplement-20261103/analysis/A/summary.json'));jobs=load_local(sup/'A-jobs.json');assert len(jobs)==1536
  cases=collections.defaultdict(dict);totals={a:collections.Counter() for a in A['statusTotals']}
  for j in jobs:
   out=member_path(j['output']);x,digest=raw(out+'/block-result.json');r,_=raw(out+'/process-receipt.json');plan,pdigest=raw(j['plan'])
   assert r['passed'] and r['exitCode']==0 and r['outputSha256']==digest
   assert pdigest==j['planSha256']==x['planSha256'] and x['completed']
   assert x['scenarioId']==j['scenarioId'] and x['blockIndex']==j['blockIndex']
   assert [s['algorithmId'] for s in x['samples']]==plan['algorithms']
   assert j['blockIndex'] not in cases[j['scenarioId']]
   cases[j['scenarioId']][j['blockIndex']]={s['algorithmId']:s['dynamicHandlingMillisecondsPerScheduledEvent'] for s in x['samples']}
   for s in x['samples']:
    for k in A['statusTotals'][s['algorithmId']]:totals[s['algorithmId']][k]+=s[k]
  assert len(cases)==32 and all(set(x)==set(range(1,49)) for x in cases.values())
  means={}
  for a in totals:
   assert dict(totals[a])==A['statusTotals'][a]
   means[a]=math.exp(statistics.mean(statistics.mean(math.log(v[a]) for v in bs.values()) for bs in cases.values()))
   close(means[a],A['geometricMeanP1_ms_per_event'][a])
  ps=[]
  for c in A['contrasts']:
   a,b=c['numerator'],c['denominator'];xs=[statistics.mean(math.log(v[a]/v[b]) for v in bs.values()) for bs in cases.values()]
   m=statistics.mean(xs);se=statistics.stdev(xs)/math.sqrt(32);z=statistics.NormalDist().inv_cdf(.995)
   close(math.exp(m),c['ratio']);close(se,c['logSE']);close(math.exp(m-z*se),c['ci99_low']);close(math.exp(m+z*se),c['ci99_high'])
   p=math.erfc(abs(m/se)/math.sqrt(2)) if a=='IDFF' and b=='C-FF' else .5*math.erfc(-m/se/math.sqrt(2))
   close(p,c['p_unadjusted_prespecified']);ps.append(p)
  running=0
  for j,i in enumerate(sorted(range(5),key=ps.__getitem__)):
   running=max(running,min(1,ps[i]*(5-j)));close(running,A['contrasts'][i]['p_holm_5'])
  bjobs=load_local(sup/'B-formal-jobs.json');assert len(bjobs)==768
  condition=collections.defaultdict(list);ids=set();movement_blocks=0
  for j in bjobs:
   x,digest=raw(j['outputPath']);receipt,_=raw(member_path(j['outputPath']).rsplit('/',1)[0]+'/process-receipt.json')
   assert receipt['passed'] and receipt['exitCode']==0 and receipt['outputSha256']==digest
   assert x['status']=='COMPLETE' and x['completeFourAlgorithmBlock'] and x['blockId']==j['block']['blockId'] and x['blockId'] not in ids
   ids.add(x['blockId'])
   if x['movement']:movement_blocks+=1
   for s in x['movement']:
    assert s['allUnitsArrived'] and s['arrivedCount']==128
    assert all(s[k]==0 for k in ['invalidPlanCount','internalFailureCount','m5CriticalViolationCount','activeAtCapCount','noPathCount','budgetExceededCount'])
    condition[(x['conditionId'],s['productionAlgorithmId'])].append(s)
  assert len(condition)==32 and all(len(v)==48 for v in condition.values()) and movement_blocks==384
  with (repository_path('supplement-20261103/analysis/B/condition-summary.csv')).open(encoding='utf-8-sig',newline='') as f:
   for row in csv.DictReader(f):
    vals=condition[(row['condition'],row['algorithm'])]
    close(float(row['meanSimulationSeconds']),statistics.mean(s['m1Seconds'] for s in vals))
    close(float(row['meanCommonMaskPathLength']),statistics.mean(s['m2CommonMaskMeanPathLength'] for s in vals))
  print(json.dumps({'status':'PASS','A_blocks':1536,'A_scenarios':32,'A_means_ms_per_event':means,'A_five_ratios_intervals_and_Holm_verified':True,'B_processes':768,'B_movement_blocks':384,'B_movement_samples':1536,'B_condition_means_verified':32,'raw_member_reads_hash_verified':read_count,'scope':'Selected numerical reproduction; not the full historical analysis suite or full B decision engine'},indent=2))
 finally:
  for z in handles.values():z.close()
if __name__=='__main__':main()
