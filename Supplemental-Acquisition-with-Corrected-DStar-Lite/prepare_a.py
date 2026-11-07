from pathlib import Path
import json,hashlib,datetime,shutil
ROOT=Path('H:/DDM_Final_Project'); OUT=Path('C:/Users/bdscy/DDM_Revision_20261103')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def write(p,x):
 p.parent.mkdir(parents=True,exist_ok=True)
 with p.open('x',encoding='utf-8') as f:json.dump(x,f,ensure_ascii=False,indent=2)
old=ROOT/'Research/FormalRuns/Gate13R_RQAligned_S48H48/v4/campaigns'
sources=[]
for p in sorted((ROOT/'Assets/_Scripts/Research').rglob('*.cs')):
 if '/Editor/' not in p.as_posix() and '/Revision20261103/' not in p.as_posix(): sources.append({'path':str(p),'sha256':sha(p)})
for rel in ['Assets/_Scripts/Research/Editor/Revision20261103Planning.cs','Assets/_Scripts/Research/Editor/ResearchPlanningBatchCommand.cs']:
 p=ROOT/rel;sources.append({'path':str(p),'sha256':sha(p)})
cases=[]
for d in sorted(old.glob('*--shared')):
 m=json.loads((d/'blocks/b0001/block-manifest.json').read_text(encoding='utf-8-sig'))
 p=ROOT/m['scenarioRelativePath'];assert sha(p)==m['scenarioSourceSha256']
 dest=OUT/'inputs/A'/p.name;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(p,dest)
 cases.append({'scenarioId':m['campaignId'].removesuffix('--shared'),'scenarioPath':str(dest),'scenarioSha256':sha(dest),'historicalManifest':str(d/'blocks/b0001/block-manifest.json')})
assert len(cases)==32
write(OUT/'A-cases.json',cases);write(OUT/'A-source-bindings.json',sources)
ids=['A*-R','D*L','C-FF','IDFF'];jobs=[]
for b in range(1,49):
 for c in cases:
  p={'studyId':'DDM-Revision-20261103-A',**c,'outputRoot':str(OUT),'blockIndex':b,'algorithms':[ids[(i+b-1)%4] for i in [0,1,3,2]],'bindings':sources}
  path=OUT/'plans/A'/f'{c["scenarioId"]}-b{b:02}.json';write(path,p)
  jobs.append({'module':'A','scenarioId':c['scenarioId'],'blockIndex':b,'plan':str(path),'planSha256':sha(path),'output':str(OUT/'formal/A'/f'{c["scenarioId"]}-b{b:02}')})
write(OUT/'A-jobs.json',jobs)
write(OUT/'authorization-and-protocol.json',{'studyId':'DDM-Revision-20261103','createdUtc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'userInstruction':'落实工作安排，做第 1 项的 A、B 两部分，并给出ETA','authorized':True,'A':{'scenarios':32,'blocksPerScenario':48,'algorithms':ids,'processes':1536,'endpoint':'same DeterministicPlanningWorkloadRunner P1; one fresh Unity Editor process per complete four-algorithm Williams block; fresh planner/input/log and forced GC boundaries','analysis':'equal campaign weights, paired log ratios; original five comparisons, Holm tests and simultaneous Bonferroni intervals; n=32 campaign means; no pooling with historical timings'},'B':{'conditions':8,'agents':128,'blocksPerCondition':48,'lanes':['movement','m4'],'processes':768,'analysis':'original completion/critical violation/callback eligibility, simulated M1 and common-mask M2; no mixing historical and new samples'},'pilot':'separate outputs excluded from formal analysis; representative runtime estimate and functional checks before collection','failurePolicy':'retain all failures; stop queue on infrastructure/validation failure; never retry individual algorithm or silently replace; new implementation attempt and explicit receipt after repair','collectionOrder':'serial processes; B followed by A; no simultaneous benchmarks','timeoutSecondsPerProcess':3600,'rawHistory':'untouched','claims':'results determine conclusions; no requirement to reproduce historical ranking'})
print(json.dumps({'cases':len(cases),'jobs':len(jobs),'bindings':len(sources),'dstar':next(x for x in sources if x['path'].endswith('DStarLitePlanner.cs'))}))
