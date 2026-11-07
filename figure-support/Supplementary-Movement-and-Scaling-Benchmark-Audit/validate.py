from pathlib import Path
import subprocess,json,hashlib,datetime,time,sys,math
import numpy as np
import pandas as pd
root=Path(__file__).resolve().parent;out=root/'analysis';src=root/'source'
def load(p):return json.loads(p.read_text(encoding='utf-8'))
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
before={p.name:digest(p) for p in out.glob('*.csv')}
numeric_before={p.name:load(p) for p in out.glob('*.json') if p.name not in ['summary.json','SUCCESS.json']}
started=datetime.datetime.now(datetime.timezone.utc).isoformat();t=time.perf_counter()
run=subprocess.run([sys.executable,'-X','utf8',str(root/'analyze.py')],capture_output=True,text=True,encoding='utf-8',timeout=600,cwd=root)
(out/'validation_rerun_stdout.txt').write_text(run.stdout,encoding='utf-8');(out/'validation_rerun_stderr.txt').write_text(run.stderr,encoding='utf-8')
assert run.returncode==0,(run.returncode,run.stderr)
assert before=={p.name:digest(p) for p in out.glob('*.csv')}
assert all(load(out/n)==v for n,v in numeric_before.items())
# Independently reconstruct the five GLS sandwich variances using explicit
# per-cluster matrix operations rather than the main einsum implementation.
data=pd.read_json(src/'lane-estimands.v1.jsonl',lines=True).sort_values(['superblockId','algorithm']).reset_index(drop=True)
import importlib.util
spec=importlib.util.spec_from_file_location('original',src/'gate14re_me_formal_st_analysis_v1_3.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
X,cols,indices,centers=m.build_design_matrix(data.to_dict(orient='records'));d=load(src/'model-fit-diagnostics.v1.json');reported=load(out/'cluster_robust_reference_contrasts.json');check=[]
names={'D1_GEOMETRIC_MEAN':'d1GeometricMeanMilliseconds','D1_NEAREST_RANK_P95':'d1NearestRankP95Milliseconds','D2':'d2GridAccessorCalls','D3':'d3TotalManagedAllocationBytes','D4':'d4MaxPersistentStateBytes'}
for r in reported:
    name=r['outcome'];model=d['models'][name];b=np.array([model['coefficients'][c] for c in cols]);sigma=model['variance']['residual'];tau=model['variance']['superblockRandomIntercept'];y=np.asarray(data[names[name]],dtype=float);y=np.log1p(y) if name in ['D3','D4'] else np.log(y)
    info=np.zeros((34,34));meat=np.zeros((34,34))
    for start in range(0,7776,6):
        xx=X[start:start+6];err=y[start:start+6]-xx@b;V=np.eye(6)*sigma+np.ones((6,6))*tau
        vx=np.linalg.solve(V,xx);ve=np.linalg.solve(V,err);info+=xx.T@vx;score=xx.T@ve;meat+=np.outer(score,score)
    bread=np.linalg.inv(info);cov=1296/1295*7775/(7776-34)*bread@meat@bread
    c=np.zeros(34);c[indices['algorithm[C-FF]']]=-1;se=np.sqrt(c@cov@c)
    assert math.isclose(se,r['cluster_cr1_se'],rel_tol=1e-10,abs_tol=1e-12)
    modelse=np.sqrt(c@bread@c);expected=model['standardErrors']['algorithm[C-FF]'];assert math.isclose(modelse,expected,rel_tol=1e-10,abs_tol=1e-12)
    check.append({'outcome':name,'independent_cr1_se':float(se),'main_cr1_se':r['cluster_cr1_se'],'frozen_model_se_matched':True})
manifest=load(root/'source_manifest.json');assert all(digest(root/x['packaged'])==x['sha256'] for x in manifest)
receipt={'status':'EXACT_DETERMINISTIC_REPLAY_AND_INDEPENDENT_VARIANCE_CHECK','start_utc':started,'end_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'elapsed_seconds':time.perf_counter()-t,'exit_code':run.returncode,'hard_timeout_seconds':600,'csv_files_exact':len(before),'numeric_json_files_exact':len(numeric_before),'independent_matrix_checks':check,'source_files_unchanged':len(manifest)}
(out/'validation_receipt.json').write_text(json.dumps(receipt,indent=2),encoding='utf-8');print(json.dumps(receipt,indent=2))
