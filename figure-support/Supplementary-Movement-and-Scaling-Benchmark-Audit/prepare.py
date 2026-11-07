from pathlib import Path
import shutil,hashlib,json,datetime
root=Path(__file__).resolve().parent;project=Path('H:/DDM_Final_Project')
sources=[
'Research/Analysis/Gate14Re-ME/formal-st/v5/attempt-004/lane-estimands.v1.jsonl',
'Research/Analysis/Gate14Re-ME/formal-st/v5/attempt-004/model-fit-diagnostics.v1.json',
'Research/Analysis/Gate14Re-ME/formal-st/v5/attempt-004/confirmatory-results.v1.json',
'Research/Gate14Re-ME/Tools/gate14re_me_formal_st_analysis_v1_3.py',
]
ranking=project/'Research/Analysis/Gate14Re-ME/formal-st/v5/ranking-score-attempt-001'
sources += [p.relative_to(project).as_posix() for p in ranking.iterdir() if p.suffix in ['.json','.csv']]
manifest=[]
for rel in sources:
    p=project/rel;dest=root/'source'/p.name;dest.parent.mkdir(exist_ok=True)
    assert not dest.exists();shutil.copyfile(p,dest)
    h=hashlib.sha256(p.read_bytes()).hexdigest();assert hashlib.sha256(dest.read_bytes()).hexdigest()==h
    manifest.append({'original':rel,'packaged':dest.relative_to(root).as_posix(),'bytes':dest.stat().st_size,'sha256':h})
(root/'source_manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
(root/'protocol_freeze.json').write_text(json.dumps({'utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'sha256':hashlib.sha256((root/'PROTOCOL.md').read_bytes()).hexdigest()},indent=2),encoding='utf-8')
print(json.dumps({'copied':len(manifest),'bytes':sum(x['bytes'] for x in manifest)}))
