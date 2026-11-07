"""Portable entry point for complete supplemental A/B archived-data analyses."""
from pathlib import Path,PurePosixPath
import argparse,csv,hashlib,json,math,shutil,subprocess,sys,zipfile,os
ROOT=Path(__file__).resolve().parent
from tools.repository_layout import repository_path
def sha(p):
    with p.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def recorded(value):
    value=str(value).replace('\\','/');marker='/DDM_Revision_20261103/'
    if marker not in value:raise ValueError('Unknown recorded path')
    suffix=PurePosixPath(value.split(marker,1)[1])
    if suffix.is_absolute() or '..' in suffix.parts or ':' in str(suffix):raise ValueError('Unsafe recorded path')
    return 'supplement-20261103/'+suffix.as_posix()
def compare(actual,expected,path,stats):
    if isinstance(expected,dict):
        assert isinstance(actual,dict) and set(actual)==set(expected),path+' keys'
        for k in expected:compare(actual[k],expected[k],path+'/'+k,stats)
    elif isinstance(expected,list):
        assert isinstance(actual,list) and len(actual)==len(expected),path+' length'
        for i,(a,b) in enumerate(zip(actual,expected)):compare(a,b,path+'/'+str(i),stats)
    elif isinstance(expected,(int,float)) and not isinstance(expected,bool):
        assert isinstance(actual,(int,float)) and math.isclose(actual,expected,rel_tol=1e-9,abs_tol=0),(path,actual,expected)
        stats['numeric_values']+=1;stats['max_absolute_difference']=max(stats['max_absolute_difference'],abs(actual-expected))
    else:assert actual==expected,(path,actual,expected)
def compare_csv(actual,expected,stats):
    with actual.open(encoding='utf-8-sig',newline='') as f:a=list(csv.DictReader(f))
    with expected.open(encoding='utf-8-sig',newline='') as f:b=list(csv.DictReader(f))
    assert len(a)==len(b),actual.name
    for i,(x,y) in enumerate(zip(a,b)):
        assert set(x)==set(y)
        for k in x:
            try:xx,yy=float(x[k]),float(y[k])
            except ValueError:assert x[k]==y[k],(i,k);continue
            compare(xx,yy,f'{actual.name}/{i}/{k}',stats)
    stats['csv_rows']+=len(a)
def main():
    from tools.guarded_python import guard
    sys.addaudithook(guard)
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--archives',type=Path,default=ROOT.parent/'data-archives')
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--timeout',type=int,default=300)
    args=p.parse_args();out=args.output.resolve();archives=args.archives.resolve()
    if out.exists():p.error('Output already exists; select a new directory')
    if out.is_relative_to(ROOT):p.error('Use an output directory outside the repository')
    import numpy as np
    if sys.version_info<(3,11):p.error('Python 3.11 or later required; Python 3.12 tested')
    # Check originals and adaptations before executing scientific code.
    for binding in read(ROOT/'portable/adaptation-manifest.json'):
        for label,key in [('original','original_sha256'),('adapted','adapted_sha256')]:
            assert sha(repository_path(binding[label]))==binding[key],binding[label]
    sup=repository_path('supplement-20261103');wanted=set()
    for job in read(sup/'A-jobs.json'):
        base=recorded(job['output']);wanted.update([base+'/block-result.json',base+'/process-receipt.json',recorded(job['plan'])])
    for job in read(sup/'B-formal-jobs.json'):
        name=recorded(job['outputPath']);wanted.update([name,name.rsplit('/',1)[0]+'/process-receipt.json'])
    index={}
    for group in ['supplement-A','supplement-B','supplement-plans']:
        with (archives/(group+'.files.csv')).open(encoding='utf-8',newline='') as f:
            for row in csv.DictReader(f):
                if row['path'] in wanted:
                    assert row['path'] not in index,'Duplicate member';index[row['path']]=row
    assert set(index)==wanted,'Required raw records or plans are missing'
    used=sorted({r['archive'] for r in index.values()});archive_manifest={x['archive']:x for x in read(archives/'archives.json')}
    for name in used:
        assert sha(archives/name)==archive_manifest[name]['sha256'],name
    out.mkdir(parents=True);inputs=out/'inputs';inputs.mkdir();outputs=out/'results';outputs.mkdir()
    handles={}
    try:
        for name,row in sorted(index.items()):
            zname=row['archive']
            if zname not in handles:handles[zname]=zipfile.ZipFile(archives/zname)
            member=PurePosixPath(name);assert member.parts[0]=='supplement-20261103' and '..' not in member.parts
            target=inputs/Path(*member.parts[1:]);assert target.resolve().is_relative_to(inputs.resolve())
            payload=handles[zname].read(name);assert len(payload)==int(row['bytes']) and hashlib.sha256(payload).hexdigest()==row['sha256'],name
            target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(payload)
    finally:
        for z in handles.values():z.close()
    for name in ['A-jobs.json','A-oracle-verification.json','B-formal-jobs.json','B-plan.json','B-formal-authorization.json']:
        shutil.copy2(sup/name,inputs/name)
    env=dict(os.environ,PYTHONDONTWRITEBYTECODE='1',PYTHONUTF8='1')
    for module in ['a','b']:
        command=[sys.executable,str(ROOT/'tools/guarded_python.py'),str(ROOT/f'portable/analyze_{module}.py'),'--input-root',str(inputs),'--output-root',str(outputs)]
        proc=subprocess.run(command,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf-8',env=env,cwd=out,timeout=args.timeout)
        (out/f'analysis-{module}.log').write_text(proc.stdout,encoding='utf-8')
        if proc.returncode:raise RuntimeError(f'Analysis {module} failed; see {out}/analysis-{module}.log\n'+proc.stdout[-2000:])
    stats={'numeric_values':0,'max_absolute_difference':0.,'csv_rows':0}
    excluded={'A':['createdUtc'],'B':['completedUtc','pythonVersion','numpyVersion','analyzerSha256']}
    for module in ['A','B']:
        a=read(outputs/module/'summary.json');b=read(repository_path('supplement-20261103/analysis/'+module+'/summary.json'))
        for key in excluded[module]:a.pop(key,None);b.pop(key,None)
        compare(a,b,module+'/summary',stats)
        for name in (['sample-results.csv','paired-contrasts.csv'] if module=='A' else ['condition-summary.csv','paired-contrasts.csv']):
            compare_csv(outputs/module/name,repository_path('supplement-20261103/analysis/'+module+'/'+name),stats)
    selftest=read(outputs/'B/self-test.json');assert selftest['status']=='PASS' and selftest['checkCount']==10
    report={'status':'PASS','scope':'Complete supplemental A and B analyses; not historical acquisitions','python_version':sys.version,'numpy_version':np.__version__,'archives_used':used,'raw_files_verified_and_extracted':len(index),'A_blocks':1536,'B_blocks':768,'B_original_engine_self_checks':selftest['checkCount'],'original_acquisition_path_access':'blocked by audit hook in analyzer subprocesses','summary_metadata_excluded_from_comparison':excluded,**stats}
    (out/'REPRODUCTION_RESULT.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print(json.dumps(report,indent=2));return 0
if __name__=='__main__':sys.exit(main())
