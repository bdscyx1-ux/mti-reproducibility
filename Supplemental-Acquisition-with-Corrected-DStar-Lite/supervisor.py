from pathlib import Path
import sys,json,time,datetime,subprocess,hashlib,math,statistics,traceback,os,argparse,shutil,ctypes
ROOT=Path('C:/Users/bdscy/DDM_Revision_20261103'); PROJECT='H:/DDM_Final_Project'
UNITY='H:/UnityEditor/2022.3.30f1c1/Editor/Unity.exe'; PY=sys.executable
def utc():return datetime.datetime.now(datetime.timezone.utc).isoformat()
def load(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.file_digest(open(p,'rb'),'sha256').hexdigest()
def atomic(p,x):
 p=Path(p);p.parent.mkdir(parents=True,exist_ok=True);tmp=p.with_suffix(p.suffix+'.tmp');tmp.write_text(json.dumps(x,ensure_ascii=False,indent=2),encoding='utf-8');os.replace(tmp,p)
def ajob(j,pilot=False):
 j=dict(j);folder=Path(j['output']) if not pilot else ROOT/'pilot/A-calibration'/Path(j['output']).name
 log=ROOT/('logs-pilot' if pilot else 'logs')/'A'/f"{folder.name}.log";log.parent.mkdir(parents=True,exist_ok=True)
 return dict(module='A',lane='planning',blockId=folder.name,outputPath=str(folder/'block-result.json'),outputDirectory=str(folder),argv=[UNITY,'-batchmode','-nographics','-quit','-projectPath',PROJECT,'-executeMethod','DDM.Research.Editor.Revision20261103Planning.Run','-revisionPlan',j['plan'],'-revisionPlanSha256',j['planSha256'],'-revisionOutput',str(folder),'-logFile',str(log)],design=j)
def bjob(j):return dict(j,module='B',lane=j['block']['lane'],blockId=j['block']['blockId'])
def validate(j):
 p=Path(j['outputPath']);x=load(p)
 if j['module']=='A':
  d=j['design'];plan=load(d['plan']);assert x['completed'] and x['scenarioId']==d['scenarioId'] and x['blockIndex']==d['blockIndex'] and x['planSha256']==d['planSha256']
  assert [s['algorithmId'] for s in x['samples']]==plan['algorithms']
  for i,s in enumerate(x['samples'],1):
   assert s['completed'] and s['usesFixedScenarioStarts'] and s['scheduledEventCount']>0
   assert math.isfinite(s['dynamicHandlingMillisecondsPerScheduledEvent']) and s['dynamicHandlingMillisecondsPerScheduledEvent']>0
   assert s==load(p.parent/f'p{i}/workload-result.json')
   assert (p.parent/f'p{i}/operations.jsonl').stat().st_size>0
  assert len({(s['scenarioFingerprintSha256'],s['planOperationCount'],s['repairOperationCount']) for s in x['samples']})==1
 else:
  d=j['block'];assert x['status']=='COMPLETE' and x['studyId']=='DDM-Revision-20261103-B'
  for k in ('blockId','conditionId','scenarioId','scenarioSha256','unitCount','blockIndex','lane','module'):assert x[k]==d[k],k
  assert x['completeFourAlgorithmBlock']
  samples=x['movement'] if d['lane']=='movement' else x['m4'];assert len(samples)==4
  assert [s['productionAlgorithmId'] for s in samples]==d['algorithmIdsInOrder']
  assert [s['algorithmLabel'] for s in samples]==d['algorithmLabelsInOrder']
  if d['lane']=='movement':
   for s in samples:
    assert len(s['units'])==128 and len({u['agentId'] for u in s['units']})==128
    assert sum(s[k] for k in ['arrivedCount','activeAtCapCount','noPathCount','budgetExceededCount','invalidPlanCount','internalFailureCount'])==128
    assert 0<=s['m1Seconds']<=180
  else:
   for s in samples:assert s['nearestRankP95FrameTimeSeconds']>0 and math.isfinite(s['nearestRankP95FrameTimeSeconds'])
 return sha(p)
def runone(j,state,index,total):
 folder=Path(j['outputDirectory']);assert not folder.exists(),f'Output exists: {folder}'
 if j['module']=='B':folder.mkdir(parents=True)
 start=time.monotonic();started=utc()
 stdout=ROOT/'supervisor-process-output.log'
 with stdout.open('ab') as f:proc=subprocess.Popen(j['argv'],stdout=f,stderr=f,creationflags=subprocess.CREATE_NO_WINDOW)
 receipt=dict(module=j['module'],lane=j['lane'],blockId=j['blockId'],pid=proc.pid,startedUtc=started,passed=False)
 while proc.poll() is None:
  state.update(current={**receipt,'elapsedSeconds':round(time.monotonic()-start,1)},updatedUtc=utc(),completed=index,total=total)
  atomic(ROOT/'status.json',state)
  if time.monotonic()-start>3600:
   atomic(ROOT/'timeout-notice.json',dict(pid=proc.pid,action='hard timeout reached; terminating owned experiment',utc=utc()))
   proc.kill();proc.wait();receipt.update(exitCode=proc.returncode,timedOut=True,finishedUtc=utc(),wallSeconds=time.monotonic()-start);folder.mkdir(parents=True,exist_ok=True);atomic(folder/'process-receipt.json',receipt);raise RuntimeError('Hard timeout: '+j['blockId'])
  time.sleep(2)
 receipt.update(exitCode=proc.returncode,finishedUtc=utc(),wallSeconds=time.monotonic()-start)
 try:
  assert proc.returncode==0,f"Process exit {proc.returncode}: {j['blockId']}"
  receipt['outputSha256']=validate(j);receipt['passed']=True
 finally:
  folder.mkdir(parents=True,exist_ok=True);atomic(folder/'process-receipt.json',receipt)
 return receipt
def main():
 parser=argparse.ArgumentParser();parser.add_argument('mode',choices=['pilot','formal']);a=parser.parse_args()
 state=dict(studyId='DDM-Revision-20261103',status='RUNNING',mode=a.mode,supervisorPid=os.getpid(),startedUtc=utc())
 try:
  ctypes.windll.kernel32.SetThreadExecutionState(0x80000001)
  assert load(ROOT/'A-oracle-verification.json')['passed'],'Oracle check failed'
  aa=load(ROOT/'A-jobs.json');bb=load(ROOT/('B-pilot-jobs.json' if a.mode=='pilot' else 'B-formal-jobs.json'))
  if a.mode=='pilot':
   picks=[0,4,8,12,16,20,24,28,31]
   jobs=[bjob(j) for j in bb if j['block']['blockIndex']==1]+[ajob(aa[i],True) for i in picks]
  else:
   assert load(ROOT/'pilot-complete.json')['passed']
   bindings=load(ROOT/'execution-freeze.json')['bindings']
   for b in bindings:assert sha(b['path'])==b['sha256'],'Frozen execution file changed: '+b['path']
   jobs=[bjob(j) for j in sorted(bb,key=lambda j:(j['block']['blockIndex'],j['block']['conditionId'],j['block']['lane']))]+[ajob(j) for j in aa]
   assert len(jobs)==2304
  receipts=[]
  for i,j in enumerate(jobs):
   if a.mode=='formal':
    for b in bindings:assert sha(b['path'])==b['sha256'],'Frozen execution file changed: '+b['path']
   if shutil.disk_usage(ROOT).free<10*1024**3:raise RuntimeError('Less than10GiB free in study volume; stopped before next block')
   r=runone(j,state,i,len(jobs));receipts.append(r)
   with (ROOT/(a.mode+'-ledger.jsonl')).open('a',encoding='utf-8') as f:f.write(json.dumps(r)+'\n')
   state['lastCompleted']=r;state['completed']=i+1
   rates={k:statistics.mean(x['wallSeconds'] for x in receipts if (x['module'],x['lane'])==k) for k in {(x['module'],x['lane']) for x in receipts}}
   state['meanBlockSeconds']={':'.join(k):v for k,v in rates.items()}
   if a.mode=='formal':state['etaSeconds']=sum(rates.get((x['module'],x['lane']),load(ROOT/'pilot-complete.json')['meanBlockSeconds'].get(':'.join((x['module'],x['lane'])),40)) for x in jobs[i+1:])
   atomic(ROOT/'status.json',state)
  state.update(status='ACQUISITION_COMPLETE',current=None,completed=len(jobs),completedUtc=utc())
  atomic(ROOT/(a.mode+'-complete.json'),dict(passed=True,**state));atomic(ROOT/'status.json',state)
  if a.mode=='formal':
   for script in ['analyze_a.py','analyze_b.py']:
    state.update(status='ANALYZING',analysisScript=script);atomic(ROOT/'status.json',state)
    subprocess.run([PY,str(ROOT/script)],check=True,creationflags=subprocess.CREATE_NO_WINDOW)
   state.update(status='COMPLETE_ANALYSIS_READY',completedUtc=utc());atomic(ROOT/'status.json',state)
 except BaseException as e:
  state.update(status='STOPPED_ERROR',error=str(e),traceback=traceback.format_exc(),updatedUtc=utc());atomic(ROOT/'status.json',state);raise
 finally:ctypes.windll.kernel32.SetThreadExecutionState(0x80000000)
if __name__=='__main__':main()
