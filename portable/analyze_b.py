"""Analyze only newly acquired B main conditions; fail closed on incomplete data."""
import argparse,collections,csv,hashlib,importlib.util,json,math,pathlib,statistics,sys,datetime
from portable_paths import configuration, resolve_recorded_path
ARGS=configuration()
ROOT=ARGS.input_root
OUTPUT=ARGS.output_root
SOURCE=pathlib.Path(__file__).resolve().parents[1]/'Supplemental-Acquisition-with-Corrected-DStar-Lite/evidence/Analyze-Gate14ReFormalPhaseBV1.py'
SOURCE_HASH='9c5bbbadfa06afc3ad715c5ceb579f4f10e8f022b694e50c37c0caeb4c217401'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def require(ok,msg):
 if not ok:raise ValueError(msg)
def dump(p,obj):
 with p.open('x',encoding='utf-8') as f:json.dump(obj,f,ensure_ascii=False,indent=2,allow_nan=False);f.write('\n')
def load_engine():
 require(sha(SOURCE)==SOURCE_HASH,'Frozen analysis source changed')
 spec=importlib.util.spec_from_file_location('original_b_analysis',SOURCE);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m

def acquire_blocks():
 jobs=read(ROOT/'B-formal-jobs.json');plan=read(ROOT/'B-plan.json');auth=read(ROOT/'B-formal-authorization.json')
 require(len(jobs)==len(plan['blocks'])==768,'Exactly 768 planned jobs required')
 require(auth['analysisRole']=='formal-acquisition','Pilot authorization prohibited')
 require(sha(ROOT/'B-plan.json')==auth['planSha256'],'Plan binding changed')
 expected={b['blockId']:b for b in plan['blocks']};seen=set();blocks=[];audit=[]
 for job in jobs:
  b=job['block'];bid=b['blockId'];require(bid in expected and b==expected[bid] and bid not in seen,'Duplicate or changed planned block');seen.add(bid)
  path=resolve_recorded_path(job['outputPath'],ROOT).resolve();require(path.is_relative_to((ROOT/'B').resolve()),'Nonformal input prohibited')
  require(path.is_file(),'Incomplete acquisition: missing '+str(path))
  block=read(path);digest=sha(path)
  require(block.get('schema')=='revision20261103-b-output-v1' and block.get('studyId')=='DDM-Revision-20261103-B' and block.get('status')=='COMPLETE','Output identity/status mismatch '+bid)
  for k in ('blockId','module','lane','conditionId','scenarioId','scenarioSha256','unitCount','blockIndex','williamsRow'):
   require(block.get(k)==b[k],'Block binding mismatch '+bid+' '+k)
  require(block['blockSequence']==b['sequence'],'Sequence mismatch')
  for k in ('planSha256','executableSha256','assemblyCSharpSha256','buildReceiptSha256','authorizationId'):require(block[k]==auth[k],'Build/auth mismatch '+bid+' '+k)
  require(block.get('completeFourAlgorithmBlock') is True and block.get('formalObservationProduced') is True,'Incomplete block '+bid)
  samples=block['movement'] if b['lane']=='movement' else block['m4']
  require(len(samples)==4 and len(block['m4'] if b['lane']=='movement' else block['movement'])==0,'Mixed or partial lane')
  require([x['algorithmLabel'] for x in samples]==b['algorithmLabelsInOrder'],'Algorithm label/order mismatch')
  require([x['productionAlgorithmId'] for x in samples]==b['algorithmIdsInOrder'],'Algorithm ID/order mismatch')
  for pos,x in enumerate(samples,1):
   require(x['orderPosition']==pos and x['unitCount']==128,'Sample identity mismatch')
   if b['lane']=='movement':
    require(len(x['units'])==128 and sorted(u['agentId'] for u in x['units'])==list(range(128)),'Agent identity mismatch')
    require(sum(x[k] for k in ('arrivedCount','activeAtCapCount','noPathCount','budgetExceededCount','invalidPlanCount','internalFailureCount'))==128,'Terminal count mismatch')
    require(math.isfinite(x['m1Seconds']) and 0<x['m1Seconds']<=180,'Invalid M1')
    require(x['allUnitsArrived']==(x['arrivedCount']==128),'Completion flag mismatch')
   else:
    raw=x['frameIntervalsSeconds'];require(x['warmupRenderedFrames']==600 and x['measuredRenderedFrameIntervals']==len(raw)==1800,'M4 sample count')
    require(all(math.isfinite(v) and v>=0 for v in raw),'Invalid callback interval')
    require(x['unitsWithEnabledRenderer']==128,'Renderer population mismatch')
    require(math.isclose(statistics.median(raw),x['medianFrameTimeSeconds'],rel_tol=1e-10,abs_tol=1e-12),'M4 median mismatch')
    require(math.isclose(sorted(raw)[math.ceil(.95*len(raw))-1],x['nearestRankP95FrameTimeSeconds'],rel_tol=1e-10,abs_tol=1e-12),'M4 P95 mismatch')
  if b['lane']=='movement':
   mask=block['m2CommonMaskAgentIds'];require(len(mask)==len(set(mask)) and all(0<=i<128 for i in mask),'Invalid common mask')
   require(block['m2CommonMaskMinimum']==103 and block['m2CommonMaskSufficient']==(len(mask)>=103),'Mask threshold mismatch')
   for x in samples:
    require(x['m2CommonMaskCount']==len(mask) and x['m2CommonMaskSufficient']==block['m2CommonMaskSufficient'],'Sample mask mismatch')
    if mask:
     units={u['agentId']:u for u in x['units']};require(all(units[i]['arrived'] for i in mask),'Mask includes non-arrival')
     mean=statistics.mean(units[i]['cumulativeHorizontalPathLength'] for i in mask)
     require(math.isclose(mean,x['m2CommonMaskMeanPathLength'],rel_tol=1e-10,abs_tol=1e-10),'M2 mean mismatch')
  rp=path.parent/'process-receipt.json';receipt_hash=None
  require(rp.is_file(),'Missing supervisor receipt '+bid)
  if rp.exists():
   rec=read(rp);require(rec.get('passed') is True and rec.get('outputSha256')==digest,'Supervisor receipt failure/hash mismatch '+bid)
   require(rec.get('exitCode',0)==0,'Supervisor nonzero exit');receipt_hash=sha(rp)
  audit.append(dict(blockId=bid,path=str(path),sha256=digest,processReceiptSha256=receipt_hash));blocks.append(block)
 counts=collections.Counter((b['conditionId'],b['lane']) for b in blocks)
 require(len(counts)==16 and set(counts.values())=={48},'Incomplete condition coverage')
 return blocks,audit

def main():
 args=ARGS
 engine=load_engine();selftest=engine.run_self_test(None)
 if args.check:
  print(json.dumps(dict(status='PASS',analysisSourceSha256=SOURCE_HASH,checkCount=selftest['checkCount'],pythonVersion=sys.version,numpyVersion=engine.np.__version__,formalDataOpened=False),ensure_ascii=False));return
 destination=OUTPUT/'B';require(not destination.exists(),'Final analysis already exists; refusing overwrite')
 blocks,audit=acquire_blocks()
 eligibility=engine.evaluate_eligibility(blocks);m1=engine.build_pairwise(blocks,metric='M1');m2=engine.build_pairwise(blocks,metric='M2');decision=engine.adjudicate_winner(eligibility,m1,m2);descriptive=engine.descriptive_algorithm_summaries(blocks)
 summary=dict(schema='revision20261103-b-analysis-v1',studyId='DDM-Revision-20261103-B',status='COMPLETE',blockCount=768,movementBlocks=384,callbackBlocks=384,algorithmSamples=3072,analysisSourceSha256=SOURCE_HASH,analyzerSha256=sha(pathlib.Path(__file__)),zeroVarianceConvention='Original deterministic convention retained: a zero-variance paired log contrast uses point intervals; p=1 for exactly zero contrast, p=0 for nonzero contrast. These finite-input results do not establish population certainty.',scope='Eight fixed main conditions N128, short trajectories after initial disjoint block/unblock; callbacks are batch-mode main-loop diagnostics, not displayed frame or interaction latency.',eligibility=eligibility,m1=m1,m2=m2,decision=decision,descriptive=descriptive,pythonVersion=sys.version,numpyVersion=engine.np.__version__,completedUtc=datetime.datetime.now(datetime.timezone.utc).isoformat())
 rows=[]
 for c in engine.CONDITIONS:
  for label in engine.ALGORITHMS:
   mov=[engine.sample_map(b)[label] for b in blocks if b['conditionId']==c and b['lane']=='movement'];cb=[engine.sample_map(b)[label] for b in blocks if b['conditionId']==c and b['lane']=='m4']
   rows.append(dict(condition=c,algorithm=engine.PRODUCTION[label],nBlocks=48,completedBlocks=sum(x['allUnitsArrived'] for x in mov),arrivedAgents=sum(x['arrivedCount'] for x in mov),invalidPlans=sum(x['invalidPlanCount'] for x in mov),internalFailures=sum(x['internalFailureCount'] for x in mov),criticalViolations=sum(x['m5CriticalViolationCount'] for x in mov),meanSimulationSeconds=statistics.mean(x['m1Seconds'] for x in mov),meanCommonMaskPathLength=statistics.mean(x['m2CommonMaskMeanPathLength'] for x in mov if x['m2CommonMaskSufficient']),meanCallbackMedianSeconds=statistics.mean(x['medianFrameTimeSeconds'] for x in cb),meanCallbackP95Seconds=statistics.mean(x['nearestRankP95FrameTimeSeconds'] for x in cb)))
 destination.mkdir(parents=True)
 dump(destination/'summary.json',summary);dump(destination/'input-manifest.json',audit);dump(destination/'self-test.json',selftest)
 with (destination/'condition-summary.csv').open('x',encoding='utf-8-sig',newline='') as f:
  w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
 pairrows=[]
 for metric,payload in [('M1',m1),('M2',m2)]:
  for row in payload['pairs']:
   pairrows.append(dict(metric=metric,pair=row['pair'],ratio=row['ratioEstimate'],simultaneousLower=row['simultaneous95RatioCI'][0],simultaneousUpper=row['simultaneous95RatioCI'][1],holmP=row['holmAdjustedTwoSidedP']))
 with (destination/'paired-contrasts.csv').open('x',encoding='utf-8-sig',newline='') as f:
  w=csv.DictWriter(f,fieldnames=list(pairrows[0]));w.writeheader();w.writerows(pairrows)
 text=['本次 B 补充实验结果','仅使用本次新采集数据，未合并历史样本。','完整采集 768 个四算法块，其中运动和 callback 各 384 块。','条件范围为 8 个主条件，N=128，每条件每通道 48 块。','合格算法：'+', '.join(eligibility['eligibleProductionAlgorithms']),'原规则判定：'+decision['status'],'被规则选中的算法：'+str(decision['winnerProductionAlgorithmId']),'']
 for label in engine.ALGORITHMS:
  e=eligibility['summary'][label];text.append(engine.PRODUCTION[label]+'：M3='+str(e['M3Pass'])+'；M4='+str(e['M4Pass'])+'；M5='+str(e['M5Pass']))
 text.extend(['','模拟完成时间不包含规划阻塞的墙钟等待；callback 为批模式主循环间隔，不能解释为实际显示帧延迟。','沿用原确定性零方差约定：零方差对比使用点区间；差异恰为零时 p=1，否则 p=0。点区间不表示对新地图或总体的确定性。','本次未分析数量趋势、长期运动、路径全局最优性或普遍算法优越性。'])
 with (destination/'结果说明.txt').open('x',encoding='utf-8') as f:f.write('\n'.join(text)+'\n')
 print(json.dumps(dict(status='COMPLETE',output=str(destination),decision=decision['status']),ensure_ascii=False))
if __name__=='__main__':main()
