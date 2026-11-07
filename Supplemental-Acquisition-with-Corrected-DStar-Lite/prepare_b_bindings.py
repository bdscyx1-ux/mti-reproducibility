import argparse,json,hashlib,pathlib,stat,datetime
p=argparse.ArgumentParser();p.add_argument('--build',default='C:/Users/bdscy/DDM_Revision_20261103/build');args=p.parse_args()
root=pathlib.Path('C:/Users/bdscy/DDM_Revision_20261103');build=pathlib.Path(args.build)
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
plan=root/'B-plan.json';exe=build/'Gate14ReFormalRunner.exe';assembly=build/'Gate14ReFormalRunner_Data/Managed/Assembly-CSharp.dll';receipt=build/'build-receipt.v2.json'
for f in (plan,exe,assembly,receipt):assert f.is_file(),f
r=json.loads(receipt.read_text(encoding='utf-8-sig'))
assert r['studyId']=='DDM-Revision-20261103-B' and r['status']=='PASS'
assert r['executableSha256']==sha(exe) and r['assemblyCSharpSha256']==sha(assembly)
for lane,path in [('pilot','pilot-B'),('formal','B')]:
 formalroot=root/path;formalroot.mkdir(exist_ok=True)
 auth=dict(schema='revision20261103-b-authorization-v1',studyId='DDM-Revision-20261103-B',status='AUTHORIZED',planSha256=sha(plan),executableSha256=sha(exe),assemblyCSharpSha256=sha(assembly),buildReceiptSha256=sha(receipt),formalRoot=str(formalroot).replace(chr(92),'/'),authorizationId='revision20261103-B-'+lane,userExplicitlyAuthorizedFormalPhaseA=True,userInstruction='落实工作安排，做第 1 项的 A、B 两部分，并给出ETA',authorizationScope='New B main-condition movement and callback acquisition approved in current user turn; legacy boolean name retained for shared contract compatibility',analysisRole='excluded-pilot' if lane=='pilot' else 'formal-acquisition',createdUtc=datetime.datetime.now(datetime.timezone.utc).isoformat())
 ap=root/('B-'+lane+'-authorization.json')
 with ap.open('x',encoding='utf-8') as f:json.dump(auth,f,ensure_ascii=False,indent=2)
 ap.chmod(stat.S_IREAD)
 print(str(ap),sha(ap))
 jobs=[]
 for block in json.loads(plan.read_text())['blocks']:
  folder=formalroot/block['blockId']; output=folder/'block-output.json'
  argv=[str(exe),'-batchmode','-force-d3d11','-logFile',str(folder/'player.log'),'--gate14re-mode','formal','--gate14re-project-root','H:/DDM_Final_Project','--gate14re-plan',str(plan),'--gate14re-plan-sha256',sha(plan),'--gate14re-output',str(output),'--gate14re-block-id',block['blockId'],'--gate14re-formal-authorization',str(ap),'--gate14re-formal-authorization-sha256',sha(ap)]
  jobs.append(dict(block=block,outputDirectory=str(folder),outputPath=str(output),argv=argv))
 with (root/('B-'+lane+'-jobs.json')).open('x',encoding='utf-8') as f:json.dump(jobs,f,indent=2)
