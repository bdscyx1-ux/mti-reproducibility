"""Recompute five recoverable historical studies from immutable archive members.

No Unity acquisition. AX2 is explicitly aggregate-only because its block outputs
were deleted before packaging. Output must be a fresh external directory.
"""
from pathlib import Path,PurePosixPath
import argparse,csv,hashlib,importlib.util,json,math,os,shutil,sys,zipfile
ROOT=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT/'portable/historical'))
from reproduce import compare_csv,read,sha

def compare(actual,expected,path,stats):
    if isinstance(expected,dict):
        assert isinstance(actual,dict) and set(actual)==set(expected),path+' keys'
        for k in expected:compare(actual[k],expected[k],path+'/'+k,stats)
    elif isinstance(expected,list):
        assert isinstance(actual,list) and len(actual)==len(expected),path+' length'
        for i,(a,b) in enumerate(zip(actual,expected)):compare(a,b,path+'/'+str(i),stats)
    elif isinstance(expected,(int,float)) and not isinstance(expected,bool):
        assert isinstance(actual,(int,float)) and math.isclose(actual,expected,rel_tol=1e-9,abs_tol=1e-12),(path,actual,expected)
        stats['numeric_values']+=1;stats['max_absolute_difference']=max(stats['max_absolute_difference'],abs(actual-expected))
    else:assert actual==expected,(path,actual,expected)

def write(p,value):
    p.parent.mkdir(parents=True,exist_ok=True)
    p.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

def load(p,name):
    spec=importlib.util.spec_from_file_location(name,p);m=importlib.util.module_from_spec(spec)
    sys.modules[name]=m;spec.loader.exec_module(m);return m

def extract(archives,out):
    groups=['historical-four-method','historical-confirmation','historical-movement','historical-mq','smsb-accepted-tables']
    chosen={}
    for group in groups:
        with (archives/(group+'.files.csv')).open(encoding='utf-8-sig',newline='') as f:
            for r in csv.DictReader(f):
                rel=r['path'];base=rel.rsplit('/',1)[-1]
                take=(group in ['historical-mq','smsb-accepted-tables'] or '/_control/' in rel or '/_commit/' in rel or base.endswith(('block-manifest.json','workload-result.json','block-output.json')) or '/campaigns/' not in rel and group!='historical-movement')
                if take:chosen[rel]=r
    manifest={a['archive']:a for a in read(archives/'archives.json')}
    used=sorted({r['archive'] for r in chosen.values()})
    for name in used:
        assert sha(archives/name)==manifest[name]['sha256'],name
    handles={}
    try:
        for name,r in chosen.items():
            if r['archive'] not in handles:handles[r['archive']]=zipfile.ZipFile(archives/r['archive'])
            rel=PurePosixPath(name);assert rel.parts[0]=='project' and '..' not in rel.parts and ':' not in name
            p=out/Path(*rel.parts);assert p.resolve().is_relative_to(out.resolve())
            data=handles[r['archive']].read(name)
            assert len(data)==int(r['bytes']) and hashlib.sha256(data).hexdigest()==r['sha256'],name
            p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data)
    finally:
        for z in handles.values():z.close()
    return chosen,used

def bound_project(inputs):
    # Copy small frozen sources/design records, but never the archived analysis outputs.
    src=ROOT/'project';dest=inputs/'project'
    for p in src.rglob('*'):
        if not p.is_file():continue
        rel=p.relative_to(src)
        if 'Analysis' in rel.parts[:2] or 'FormalRuns' in rel.parts or 'FormalDataPackages' in rel.parts:continue
        target=dest/rel
        if target.exists():assert sha(target)==sha(p);continue
        target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(p,target)
    return dest

def run_four(project,out):
    m=load(project/'Research/Analyze-Gate13RPR2Attempt4PhaseBV2.py','frozen_four')
    contract=read(project/'Research/Gate13R_PR2_Attempt4_PhaseB_Execution_Contract.v2.json')
    paths={k:m.verified_bound_file(project,v,k) for k,v in contract['frozenInputBindings'].items()}
    for k,v in contract['implementationBindings'].items():m.verified_bound_file(project,v,k)
    raw=project/contract['rawInput']['rootRelativePath']
    schedule=m.load_and_verify_schedule(paths['formalSchedule'],3552,10176)
    blocks,audit=m.load_formal_blocks(raw,schedule,read(paths['blockFormalEligibilityManifest']),read(paths['rawBlockEvidenceManifest']))
    shared=[b for b in blocks if b['schedule']['comparisonCohortId']==m.SHARED_COHORT]
    hetero=[b for b in blocks if b['schedule']['comparisonCohortId'] in {m.PER_AGENT_COHORT,m.GROUPED_FIELD_COHORT}]
    superblocks=m.build_matched_superblocks(hetero)
    assert (len(blocks),len(shared),len(hetero),len(superblocks))==(3552,1536,2016,1008)
    from four_outputs import compute
    for name,obj in compute(m,blocks,shared,hetero,superblocks,'OFFLINE-RECOMPUTATION').items():write(out/name,obj)
    write(out/'block-verification.json',audit);write(out/'self-test.json',m.run_self_test())
    # A normalized source table supports original-scale manuscript summaries.
    rows=[]
    for b in blocks:
        for algorithm,s in b['samples'].items():
            rows.append({'cohort':b['schedule']['comparisonCohortId'],'algorithm':algorithm,'metrics':s['metrics']})
    write(out/'sample-metrics.json',rows)

def run_confirmation(project,out):
    m=load(ROOT/'portable/historical/confirmation_engine.py','portable_confirmation')
    m.ORIGINAL_ANALYZER=project/'Research/Analyze-Gate13RP1C5IndependentPhaseBV1.py'
    m.ANALYSIS_ROOT_REL=str(out.resolve())
    auth=next((project/'Research').glob('*P1C5*PhaseB*Authorization*.json'))
    m.run_analysis(project,sha(project/m.CONTRACT_REL),auth)
    engine=load(project/'Research/Analyze-Gate13RPR2Attempt4PhaseBV2.py','frozen_confirmation_descriptives')
    rows=[]
    for rec in m.iter_jsonl(project/m.SCHEDULE_REL):
        path=project/m.RAW_ROOT_REL/rec['outputRelativePath']/'block-manifest.json'
        for sample in read(path)['samples']:
            result_path=path.parent/sample['workloadResultRelativePath']
            assert sha(result_path)==sample['workloadResultSha256']
            rows.append({'cohort':'confirmation-shared','algorithm':sample['algorithmId'],'metrics':engine.derive_metrics(read(result_path),sample)})
    write(out/'sample-metrics.json',rows)

def run_movement(project,out,chosen):
    m=load(project/'Research/Analyze-Gate14ReFormalPhaseBV1.py','frozen_movement')
    raw=project/'Research/FormalRuns/Gate14Re/PhaseA/attempt-001'
    prefix='project/'+raw.relative_to(project).as_posix()+'/'
    records=[{'relativePath':p[len(prefix):],'sha256':r['sha256']} for p,r in chosen.items() if p.startswith(prefix) and p.endswith('/block-output.json')]
    frozen=[json.loads(line) for line in (raw/'_control/raw-commit-canonical-tree.v1.jsonl').read_text('utf-8-sig').splitlines()]
    original_records={r['relativePath']:r['sha256'] for r in frozen if r['relativePath'].endswith('/block-output.json')}
    assert {r['relativePath']:r['sha256'] for r in records}==original_records,'Movement freeze manifest disagrees with selected outcomes'
    blocks=m.load_formal_blocks(raw,records)
    out.mkdir(parents=True)
    for name,obj in m.compute_outputs(blocks).items():
        if isinstance(obj,str):(out/name).write_text(obj,encoding='utf-8')
        else:write(out/name,obj)
    write(out/'self-test.json',m.run_self_test(None))
    # Reproduce the published post-hoc preference score using its released map;
    # never invoke machine-bound encrypted label custody or re-randomize labels.
    engine=load(project/'Research/Analyze-Gate14ReEngineeringRecommendationV1.py','frozen_movement_preference')
    contract=read(project/'Research/Gate14Re/EngineeringRecommendation/Gate14Re_Engineering_Recommendation_Contract.v1.json')
    release=read(ROOT/'project/Research/Analysis/Gate14Re/EngineeringRecommendation/final-attempt-001/label-mapping-release.v1.json')
    mapping={r['sourceLabel']:r['anonymousLabel'] for r in release['rows']}
    for binding in contract['staticEngineeringTiebreak']['sourceBindings']:
        target=project/binding['path']
        if not target.exists() or sha(target)!=binding['sha256']:
            matches=[p for p in ROOT.rglob('*.cs') if sha(p)==binding['sha256']]
            assert matches, 'Missing historical static-source version: '+binding['path']
            binding['path']=str(matches[0].resolve())
    derived=out.parent/'movement-preference';derived.mkdir()
    stats={'numeric_values':0,'max_absolute_difference':0.,'csv_rows':0}
    for name,obj in engine.compute_outputs(project,m,blocks,mapping,contract).items():
        if isinstance(obj,str):(derived/name).write_text(obj,encoding='utf-8')
        else:
            write(derived/name,obj)
            compare(obj,read(ROOT/'project/Research/Analysis/Gate14Re/EngineeringRecommendation/attempt-001'/name),name,stats)
    write(derived/'REPRODUCTION_RESULT.json',{'status':'PASS',**stats})

def run_mq(project,out):
    m=load(project/'Research/Gate14Re-MQ-CFF-IDFF/Analysis/v1/analyze_formal_mq_v1.py','frozen_mq')
    auth=read(project/'Research/Verification/Gate14Re-MQ-CFF-IDFF/formal-analysis-execution-attempt-001/execution-authorization.v1.json')
    audit,schedule,identity,raw=m.preflight(project,auth)
    data,structural=m.load_and_validate_batches(raw,schedule)
    rows,ids,values=m.compute_block_estimands(data,identity)
    out.mkdir(parents=True)
    (out/'block-estimands.v1.jsonl').write_bytes(m.canonical_jsonl_bytes(rows))
    write(out/'batch-wall-time-source.json',[{'blockId':bid,'algorithm':identity[slot],'condition':condition,'seconds':value} for bid,slots in data.items() for slot,cells in slots.items() for condition,value in cells.items()])
    confirm=m.apply_inference(values,identity)
    for name,obj in {
        'confirmatory-and-secondary-results.v1.json':confirm,
        'descriptive-condition-summaries.v1.json':m.condition_summaries(data,identity),
        'descriptive-and-exploratory-results.v1.json':m.descriptive_exploratory(data,values,ids,identity),
        'sensitivity-analysis.v1.json':m.sensitivity_results(values,ids),
        'statistical-validation.v1.json':m.statistical_validation(confirm),
        'input-verification.json':audit,'self-test.json':m.self_test(),
    }.items():write(out/name,obj)

def run_smsb(project,out):
    import pyarrow.parquet as pq
    m=load(project/'Research/Gate14Re-ME/Tools/gate14re_me_formal_st_analysis_v1_3.py','frozen_smsb')
    archived=ROOT/'project/Research/Analysis/Gate14Re-ME/formal-st/v5/attempt-004'
    bindings=read(archived/'analysis-manifest.v1.json')['bindings']
    package=project/'Research/FormalDataPackages/Gate14Re-ME/formal-st/v5/attempt-002'
    # Identify the frozen receipt by its hash, not the historical machine path.
    terminals=[p for p in package.glob('terminal*.json') if sha(p)==bindings['acceptanceTerminalFinalSha256']]
    assert len(terminals)==1,terminals
    schedule=project/'Research/FormalInputs/Gate14Re-ME/formal-st/v5/attempt-001/schedule/formal-st-williams-schedule.v5.jsonl'
    identity=project/'Research/Gate14Re-ME/Execution/v5_1/formal-st-algorithm-identity-binding.reused.v5_1.json'
    from smsb_outputs import compute
    out.mkdir(parents=True)
    compute(m,package,terminals[0],bindings,schedule,identity,pq,out)

def run_reporting(project,results):
    import contextlib
    base=ROOT/'project/Research/Analysis/Gate14Re-ME/formal-st/v5'
    m=load(project/'Research/Gate14Re-ME/Tools/gate14re_me_formal_st_raw_scale_provenance_v1_0.py','frozen_reporting')
    src=results/'smsb';out=results/'smsb-reporting';out.mkdir()
    lanes=[json.loads(x) for x in (src/'lane-estimands.v1.jsonl').read_text('utf-8-sig').splitlines()]
    raw,lookup=m.raw_algorithm_rows(lanes,read(src/'descriptive-summaries.v1.json'))
    confirm=read(src/'confirmatory-results.v1.json');diag=read(src/'model-fit-diagnostics.v1.json')
    tables={'raw-scale-by-algorithm.v1.csv':raw,'raw-scale-by-axis.v1.csv':m.raw_axis_rows(lanes),'formal-ratio-provenance.v1.csv':m.ratio_rows(confirm,diag,lookup),'formal-slope-provenance.v1.csv':m.slope_rows(confirm,diag)}
    tables['formal-slope-provenance.v1.csv']=[{k:v for k,v in row.items() if k!='referenceCurve'}|{'referenceCurve':m.canonical_json(row['referenceCurve'])} for row in tables['formal-slope-provenance.v1.csv']]
    stats={'numeric_values':0,'max_absolute_difference':0.,'csv_rows':0}
    for name,rows in tables.items():
        m.write_csv(out/name,rows);compare_csv(out/name,base/'attempt-004-reporting-addendum-001'/name,stats)
    for folder in [src,out]:
        rows=[{'relativePath':p.name,'sha256':sha(p),'bytes':p.stat().st_size} for p in sorted(folder.iterdir()) if p.is_file()]
        (folder/'file-manifest.v1.jsonl').write_text(''.join(json.dumps(r)+'\n' for r in rows),encoding='utf-8')
    rank=results/'ranking';rank.mkdir()
    shutil.copyfile(base/'ranking-score-attempt-001/ranking-contract.v1.json',rank/'ranking-contract.v1.json')
    r=load(base/'ranking-score-attempt-001/compute_ranking.py','frozen_ranking')
    r.ROOT=rank;r.SOURCE=src;r.ADDENDUM=out
    with (rank/'calculation.log').open('w',encoding='utf-8') as log,contextlib.redirect_stdout(log):r.main()
    for p in rank.glob('*.csv'):compare_csv(p,base/'ranking-score-attempt-001'/p.name,stats)
    actual=read(rank/'ranking-results.v1.json');expected=read(base/'ranking-score-attempt-001/ranking-results.v1.json')
    actual.pop('createdAtUtc');expected.pop('createdAtUtc');compare(actual,expected,'ranking',stats)
    return {'status':'PASS',**stats}

def run_operation_budget(archives,out):
    """Recover the two non-AX2 rows of Table S3 from actual operation records."""
    with (archives/'historical-four-method.files.csv').open(encoding='utf-8-sig',newline='') as f:
        selected=[r for r in csv.DictReader(f) if '/shared' in r['path'] or '--shared/' in r['path']]
    selected=[r for r in selected if r['path'].endswith('/operations.jsonl') and ('-astar-r/' in r['path'] or '-dstar-l/' in r['path'])]
    assert len(selected)==3072,len(selected)
    values={a:{op:[] for op in ['plan','repair']} for a in ['A*-R','D*L']};handles={}
    try:
        for r in selected:
            if r['archive'] not in handles:handles[r['archive']]=zipfile.ZipFile(archives/r['archive'])
            data=handles[r['archive']].read(r['path']);assert hashlib.sha256(data).hexdigest()==r['sha256']
            for line in data.decode('utf-8-sig').splitlines():
                item=json.loads(line)
                if item['recordType']!='planner_operation':continue
                q=item['payload'];alg=q['algorithmId'];op=q['operation']
                if op in ['plan','repair']:
                    assert float(q['budgetMilliseconds'])==10000
                    values[alg][op].append(float(q['elapsedCpuMilliseconds']))
    finally:
        for z in handles.values():z.close()
    rows=[]
    for alg,ops in values.items():
        for op,v in ops.items():
            v.sort();maximum=max(v);rows.append({'algorithm':alg,'operation':op,'n':len(v),'p95_nearest_rank_ms':v[math.ceil(.95*len(v))-1],'max_ms':maximum,'budget_ms':10000,'remaining_ms':10000-maximum,'remaining_percent':100*(10000-maximum)/10000})
    write(out/'operation-budget.json',{'source':'Original four-method shared-goal operation records','members_hashed':len(selected),'rows':rows,'AX2_rows':'RAW_MISSING_NOT_RECOMPUTED'})
    return rows

EXPECTED={
 'four-method':'Gate13R_PR2_Attempt4_PhaseB/v1',
 'confirmation':'Gate13R_P1C5_Independent/v1',
 'movement':'Gate14Re/PhaseB/attempt-001',
 'mq':'Gate14Re-MQ-CFF-IDFF/formal-mq/v1/attempt-001',
 'smsb':'Gate14Re-ME/formal-st/v5/attempt-004'}
SKIP={'generatedAtUtc'}
def clean(obj):
    if isinstance(obj,dict):return {k:clean(v) for k,v in obj.items() if k not in SKIP}
    if isinstance(obj,list):return [clean(v) for v in obj]
    return obj
def validate(name,out):
    archived=ROOT/'project/Research/Analysis'/EXPECTED[name]
    stats={'numeric_values':0,'max_absolute_difference':0.,'csv_rows':0};files=[]
    excluded={'analysis-input-audit.v1.json'}
    for actual in out.glob('*.json'):
        expected=archived/actual.name
        if not expected.exists() or actual.name in excluded:continue
        compare(clean(read(actual)),clean(read(expected)),name+'/'+actual.name,stats);files.append(actual.name)
    actual=out/'lane-estimands.v1.jsonl'
    if actual.exists():
        aa=[json.loads(x) for x in actual.read_text('utf-8-sig').splitlines()]
        bb=[json.loads(x) for x in (archived/actual.name).read_text('utf-8-sig').splitlines()]
        compare(aa,bb,name+'/'+actual.name,stats);files.append(actual.name)
    assert files,name
    return {'status':'PASS','compared_files':files,**stats}

def main():
    from tools.guarded_python import guard
    sys.addaudithook(guard)
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--archives',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();out=a.output.resolve()
    if out.exists() or out.is_relative_to(ROOT):p.error('Use a fresh output directory outside the repository')
    for b in read(ROOT/'portable/historical/original-engines.json'):assert sha(ROOT/b['path'])==b['sha256'],b['path']
    for b in read(ROOT/'portable/historical/adapter-hashes.json'):assert sha(ROOT/b['path'])==b['sha256'],b['path']
    out.mkdir(parents=True);inputs=out/'inputs';inputs.mkdir()
    print('Verifying and extracting scientific inputs...',flush=True)
    chosen,used=extract(a.archives.resolve(),inputs);project=bound_project(inputs)
    write(out/'input-verification.json',{'archives':used,'members':len(chosen),'bytes':sum(int(r['bytes']) for r in chosen.values()),'hash_verified':True,'scope':'Selected archived outcomes and control records; full accepted SMSB package and full MQ archive. Unused four-method/confirmation/movement telemetry not extracted.'})
    report={}
    for name,func in [('four-method',run_four),('confirmation',run_confirmation),('movement',lambda p,o:run_movement(p,o,chosen)),('mq',run_mq),('smsb',run_smsb)]:
        print('Computing '+name+'...',flush=True)
        func(project,out/'results'/name)
        report[name]=validate(name,out/'results'/name);write(out/'PROGRESS.json',report)
        print(name+': '+json.dumps(report[name]),flush=True)
    report['reporting-and-ranking']=run_reporting(project,out/'results')
    run_operation_budget(a.archives.resolve(),out/'results'/'operation-budget')
    report['expanded-AX2']={'status':'RAW_UNAVAILABLE_AGGREGATE_ONLY','reason':'Original block outputs deleted by historical cleanup; user reports no known backup. No raw-data replication claimed.'}
    write(out/'REPRODUCTION_RESULT.json',{'status':'PASS_FOR_FIVE_RECOVERABLE_STUDIES','studies':report,'metadata_excluded':sorted(SKIP),'input_integrity':'See input-verification.json','original_machine_paths':'Denied by Python audit hook'})

if __name__=='__main__':main()
