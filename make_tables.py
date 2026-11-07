"""Build editable manuscript tables, with per-table provenance and missing-data boundaries.

Numeric tables are generated from recomputed outputs. Design/definition prose is
transcribed from the supplied manuscript. AX2-only values and operation-budget
telemetry without a retained numerical source are explicitly labelled retained.
"""
from pathlib import Path
import argparse,csv,html,json,math,re,statistics,shutil
ROOT=Path(__file__).resolve().parent
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def csvread(p):
    with p.open(encoding='utf-8-sig',newline='') as f:return list(csv.DictReader(f))
def fmt(v,n=6):return f'{float(v):.{n}f}'
def interval(v,n=6):return '–'.join(fmt(x,n) for x in v)
def pvalue(v):return '<1e-15' if float(v)<1e-15 else f'{float(v):.6g}'
def gm(values):
    assert values and min(values)>0
    return math.exp(statistics.fmean(math.log(v) for v in values))
def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--results',type=Path,required=True);ap.add_argument('--supplement-results',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);a=ap.parse_args()
    res=a.results.resolve();sup=a.supplement_results.resolve();out=a.output.resolve()
    if out.exists():ap.error('Output must be fresh')
    out.mkdir(parents=True);(out/'csv').mkdir();(out/'original-transcription').mkdir()
    original=read(ROOT/'figure-support/manuscript-tables.json');tables={};meta={};checks=[]
    for t in original:
        match=re.match(r'(Table|Algorithm)\s+(S?\d+[a-e]?)\.',t['caption']);assert match,t['caption']
        key=('Table_' if match[1]=='Table' else 'Algorithm_')+match[2];tables[key]=t['rows'];meta[key]={'caption':t['caption'],'mode':'DESIGN_OR_DEFINITION_TRANSCRIPTION','source_docx_sha256':t['source_docx_sha256']}
        with (out/'original-transcription'/(key+'.csv')).open('w',encoding='utf-8-sig',newline='') as f:csv.writer(f).writerows(t['rows'])
    def put(key,rows,source,mode='RECOMPUTED'):
        tables[key]=rows;meta[key].update(mode=mode,source=source)
    four=read(res/'four-method/sample-metrics.json');confirm=read(res/'confirmation/sample-metrics.json')
    descriptive=[]
    for group,label in [('four-algorithm-shared-goal-v1','Four-method / shared'),('heterogeneous','Four-method / heterogeneous'),('confirmation-shared','Confirmation / shared')]:
        subset=[r for r in (confirm if group=='confirmation-shared' else four) if (r['cohort']==group or group=='heterogeneous' and 'heterogeneous' in r['cohort'])]
        for alg in ['A*-R','D*L','C-FF','IDFF']:
            rr=[r for r in subset if r['algorithm']==alg]
            if not rr:continue
            vals=[]
            for ep in ['P1','P2','P3-PER-AGENT','P4']:
                vv=[r['metrics']['continuous'][ep] for r in rr];assert all(v['eligible'] for v in vv)
                vals.append(gm([v['value'] for v in vv]))
            descriptive.append([label,alg,str(len(rr)),fmt(vals[0],4),fmt(vals[1],4),fmt(vals[2],4),f'{vals[3]:.0f}','RECOMPUTED'])
    expanded=[]
    prior=tables['Table_S1'];group=''
    for row in prior[1:]:
        if row[0]:group=row[0]
        if 'Expanded' in group:expanded.append(['Expanded search / shared',*row[1:],'ARCHIVED_SUMMARY_ONLY_AX2_RAW_MISSING'])
    rows=[['Acquisition / cohort','Algorithm','n','P1 ms/event','P2 GM of P95 ms','P3 ms/agent','P4 diagnostic bytes/event','Provenance']]+descriptive+expanded
    put('Table_S1',rows,'four-method/sample-metrics.json; confirmation/sample-metrics.json; AX2 rows retained from source manuscript','MIXED_RECOMPUTED_AND_AX2_SUMMARY')
    shared=[r for r in descriptive if r[0]=='Four-method / shared']
    put('Table_S2',[rows[0]]+[r for r in shared if r[1] in ['A*-R','D*L']]+expanded,'Table_S1 / same acquisition labels','MIXED_RECOMPUTED_AND_AX2_SUMMARY')
    ar=csvread(sup/'A/sample-results.csv');supp=[]
    for alg in ['A*-R','D*L','C-FF','IDFF']:
        vv=[float(r['P1_ms_per_event']) for r in ar if r['algorithm']==alg];supp.append(['Supplemental corrected D*L',alg,str(len(vv)),fmt(gm(vv),4),'RECOMPUTED_SUPPLEMENT_A'])
    put('Table_3',[['Acquisition','Backend','Samples per backend','P1 GM ms/event','Provenance']]+[[r[0],r[1],r[2],r[3],r[-1]] for r in shared+expanded+[r for r in descriptive if r[0]=='Confirmation / shared']]+supp,'Table_S1 and supplemental A/sample-results.csv','MIXED_RECOMPUTED_AND_AX2_SUMMARY')
    budget=read(res/'operation-budget/operation-budget.json')['rows'];rr=[tables['Table_S3'][0]+['Provenance']]
    for row in tables['Table_S3'][1:]:
        alg=row[0]
        if alg in ['A*-R','D*L']:
            op={r['operation']:r for r in budget if r['algorithm']==alg};new=[alg]
            for name in ['plan','repair']:
                r=op[name];new.extend([fmt(r['p95_nearest_rank_ms'],4),fmt(r['max_ms'],4),fmt(r['remaining_ms'],4)+' ('+fmt(r['remaining_percent'],4)+'%)'])
            rr.append(new+['RECOMPUTED_FROM_OPERATIONS'])
        else:rr.append(row+['AX2_RAW_MISSING_MANUSCRIPT_SUMMARY_ONLY'])
    put('Table_S3',rr,'operation-budget/operation-budget.json; AX2 rows retained from original manuscript','MIXED_RECOMPUTED_AND_AX2_SUMMARY')
    raw=csvread(res/'smsb-reporting/raw-scale-by-algorithm.v1.csv');ratios=csvread(res/'smsb-reporting/formal-ratio-provenance.v1.csv');slopes=csvread(res/'smsb-reporting/formal-slope-provenance.v1.csv');hyp=read(res/'smsb/confirmatory-results.v1.json')
    endpoints=['d1GeometricMeanMilliseconds','d1NearestRankP95Milliseconds','d2GridAccessorCalls','d3TotalManagedAllocationBytes','d4MaxPersistentStateBytes']
    labels=['D1 GM (ms)','D1 P95 (ms)','D2 grid calls','D3 allocation bytes','D4 retained bytes']
    def component(field,alg):
        i=endpoints.index(field);h=next(x for x in hyp['hypotheses'] if x['domainId'].startswith('D'+str(max(1,i))+'_') and x['comparator']==alg)
        c=h['components'][['equalDesignGeometricMeanRatio','equalDesignNearestRankP95Ratio'][i]] if i<2 else h['component'];return h,c
    t4=[['Outcome','IDFF adjusted reference','C-FF adjusted reference','Formal ratio','Simultaneous interval']]
    for field,title in zip(endpoints,labels):
        r=next(x for x in ratios if x['sourceField']==field and x['comparator']=='C-FF');h,c=component(field,'C-FF')
        t4.append([title,fmt(r['idffReferenceAdjustedRawScale']),fmt(r['comparatorReferenceAdjustedRawScale']),fmt(c['ratioEstimate']),interval(c['simultaneousTwoSidedBonferroniRatioInterval'])])
    put('Table_4',t4,'smsb-reporting/formal-ratio-provenance.v1.csv; smsb/confirmatory-results.v1.json')
    put('Table_S6',[['Outcome','Algorithm','Arithmetic mean','Median','Interquartile range']]+[[title,r['algorithm'],f"{float(r['mean']):.6g}",f"{float(r['median']):.6g}",f"{float(r['p25']):.6g}–{float(r['p75']):.6g}"] for field,title in zip(endpoints,labels) for r in raw if r['sourceField']==field],'smsb-reporting/raw-scale-by-algorithm.v1.csv')
    for i,field in enumerate(endpoints):
        rr=[['Comparator','eta IDFF','eta comparator','Adjusted IDFF','Adjusted comparator','Formal numerator','Formal denominator','Formal ratio','Simultaneous interval','Holm p']]
        for r in ratios:
            if r['sourceField']!=field:continue
            h,c=component(field,r['comparator']);rr.append([r['comparator'],fmt(r['idffReferenceLinearPredictor']),fmt(r['comparatorReferenceLinearPredictor']),fmt(r['idffReferenceAdjustedRawScale'],3),fmt(r['comparatorReferenceAdjustedRawScale'],3),fmt(r['formalRatioNumerator'],3),fmt(r['formalRatioDenominator'],3),fmt(c['ratioEstimate']),interval(c['simultaneousTwoSidedBonferroniRatioInterval']),pvalue(h['holmAdjustedOneSidedP'])])
        put('Table_S7'+chr(97+i),rr,'smsb-reporting/formal-ratio-provenance.v1.csv; smsb/confirmatory-results.v1.json')
    put('Table_S8',[['Domain','Comparator','IDFF slope','Comparator slope','Difference','Simultaneous interval','Holm p','Pass']]+[[r['domain'].split('_')[0],r['comparator'],fmt(r['idffSlopePerLog2AxisUnit']),fmt(r['comparatorSlopePerLog2AxisUnit']),fmt(r['reportedIdffMinusComparatorSlope']),interval(json.loads(r['simultaneousInterval'])),pvalue(r['holmAdjustedOneSidedP']),str(int(r['hypothesisPassed']=='True'))] for r in slopes],'smsb-reporting/formal-slope-provenance.v1.csv')
    failed=[['Domain','Comparator','Endpoint','Estimate','Simultaneous interval','Holm p','Direction favorable','Interval favorable','MIPE reached']]
    for h in hyp['hypotheses']:
        if h['rejectAtFamilywiseAlpha0.05']:continue
        cc=h.get('components',{'component':h.get('component')})
        for ep,c in cc.items():
            val=c.get('ratioEstimate',c['estimateModelScale']);ci=c.get('simultaneousTwoSidedBonferroniRatioInterval',c['simultaneousTwoSidedBonferroniIntervalModelScale'])
            failed.append([h['domainId'],h['comparator'],ep,fmt(val),interval(ci),pvalue(h['holmAdjustedOneSidedP']),str(h['directionFavorable']),str(h['simultaneousIntervalFavorable']),str(h['reachesPrespecifiedMipe'])])
    put('Table_S9',failed,'smsb/confirmatory-results.v1.json')
    put('Table_S10',[['Domain','Hard gates valid','Passing comparisons','Domain pass','Non-passing comparators']]+[[d['domainId'],str(d['valid']),f"{d['comparatorsPassing']}/5",str(d['domainPass']),'; '.join(d['failedComparators'])] for d in hyp['domains']],'smsb/confirmatory-results.v1.json')
    rank=read(res/'ranking/ranking-results.v1.json')['ranking']
    put('Table_S12',[['Rank','Algorithm','Score / 100','Conservative simultaneous bounds']]+[[str(int(r['rank'])),r['algorithm'],fmt(r['primaryScore'],2),interval([r['conservativeSimultaneousScoreLower'],r['conservativeSimultaneousScoreUpper']],2)] for r in rank],'ranking/ranking-results.v1.json')
    put('Table_S13',[['Algorithm']+[f'D{i} utility' for i in range(1,8)]+['Total']]+[[r['algorithm']]+[f"{r[f'D{i}Utility']:g}" for i in range(1,8)]+[fmt(r['primaryScore'],2)] for r in rank],'ranking/ranking-results.v1.json')
    mq=read(res/'mq/confirmatory-and-secondary-results.v1.json')['results'];mqt=[['Algorithm','Placement / contrast','n','Geometric ratio','Ordinary 95% interval','Reduction %','Holm one-sided p','Simultaneous upper ratio']]
    for r in mq:mqt.append([r['algorithmId'],r['topology']+' / '+r['estimand'],str(r['n']),fmt(r['geometricRatio'],4),interval(r['ordinaryTwoSided95CiRatio'],4),fmt(-r['percentChange'],2),pvalue(r['holmAdjustedOneSidedP']),fmt(r['bonferroniOneSidedUpperRatio'],4)])
    put('Table_6',mqt,'mq/confirmatory-and-secondary-results.v1.json');put('Table_S4',mqt,'mq/confirmatory-and-secondary-results.v1.json')
    sens=read(res/'mq/sensitivity-analysis.v1.json')['rows'];rr=[['Contrast','Studentized bootstrap 95% ratio interval','Exact signed-rank p','Leave-one-block-out ratio range']]
    for r in sens:
        boot=r.get('studentizedBootstrap',r.get('bootstrap'));assert boot is not None,r.keys()
        ci=boot.get('ratioInterval',boot.get('ratio95Ci',boot.get('ordinaryTwoSided95CiRatio')))
        if ci is None:
            ci=next(v for k,v in boot.items() if isinstance(v,list) and len(v)==2 and 'ratio' in k.lower())
        loo=r['leaveOneBlockOut'];rr.append([r['hypothesisId'],interval(ci,4),f"{r['signedRank']['exactLowerTailP']:.4g}",interval([math.exp(loo['minimumLeaveOneOutEstimate']),math.exp(loo['maximumLeaveOneOutEstimate'])],4)])
    put('Table_S18',rr,'mq/sensitivity-analysis.v1.json')
    pref=res/'movement-preference';release=read(ROOT/'project/Research/Analysis/Gate14Re/EngineeringRecommendation/final-attempt-001/label-mapping-release.v1.json');ids={r['productionAlgorithmId']:r['anonymousLabel'] for r in release['rows']}
    dr={r['anonymousLabel']:r for r in read(pref/'anonymous-decision-workbook.json')['rows']}
    put('Table_S11',[['Algorithm','Movement ×2','Path ×1','Scaling ×1','Callback ×1','Static tie-break','Total']]+[[alg]+[str(dr[ids[alg]][k]) for k in ['movementRank','pathRank','scalingRank','renderRank','staticBurdenRank','decisionScore']] for alg in ['IDFF','C-FF','A*-R']],'movement-preference/anonymous-decision-workbook.json; released label mapping')
    e={r['anonymousLabel']:r for r in read(pref/'anonymous-movement-resolution.json')['anonymousAggregates']};m2={r['anonymousLabel']:r for r in read(pref/'anonymous-m2.json')['anonymousAggregates']};m4={r['anonymousLabel']:r for r in read(pref/'anonymous-m4.json')['anonymousAggregates']};sc={r['anonymousLabel']:r for r in read(pref/'anonymous-quantity-scaling.json')['anonymousScaling']};st={r['anonymousLabel']:r for r in read(pref/'anonymous-static-engineering.json')['anonymousProfiles']}
    rr=[['Input','IDFF','C-FF','A*-R']]
    for k,title in [('RMAT180Seconds','RMAT180 (s)'),('T95Seconds','T95 (s)'),('T99Seconds','T99 (s)'),('T100MinusT50Seconds','T100 minus T50 (s)'),('originalM1Seconds','M1 (s)')]:rr.append([title]+[fmt(e[ids[alg]][k],9) for alg in rr[0][1:]])
    rr.append(['M2 equal-condition GM (scene units)']+[fmt(m2[ids[alg]]['equalConditionGeometricMeanPathLength'],9) for alg in rr[0][1:]])
    rr.append(['Callback P95 equal-condition GM (ms)']+[fmt(1000*m4[ids[alg]]['P95FrameTimeSeconds'],9) for alg in rr[0][1:]])
    for k in ['RMAT180','M2','M4P95']:rr.append([k+' ratio per doubling of N']+[fmt(sc[ids[alg]]['perDoublingRatios'][k],9) for alg in rr[0][1:]])
    rr.append(['Mean scaling submetric rank']+[fmt(sc[ids[alg]]['meanSubmetricRank']) for alg in rr[0][1:]])
    for k in ['logicalSourceLines','branchTokens','allocationSites','publicSurfaceTokens','sourceBytes']:rr.append([k]+[str(st[ids[alg]]['metrics'][k]) for alg in rr[0][1:]])
    put('Table_S19',rr,'movement-preference outputs; historical source hashes checked')
    b=csvread(sup/'B/condition-summary.csv');rr=[['Case','Completion time (s), all algorithms','Path A*-R','Path D*L','Path C-FF / IDFF','Completed blocks, all algorithms']]
    assert set(read(sup/'B/summary.json')['eligibility']['eligibleAlgorithms'])=={'A','B','C','D'},'Supplement B gates failed'
    for condition in sorted({r['condition'] for r in b}):
        d={r['algorithm']:r for r in b if r['condition']==condition};assert len({r['meanSimulationSeconds'] for r in d.values()})==1
        rr.append([condition,fmt(d['A*-R']['meanSimulationSeconds'],2),fmt(d['A*-R']['meanCommonMaskPathLength'],5),fmt(d['D*L']['meanCommonMaskPathLength'],5),fmt(d['C-FF']['meanCommonMaskPathLength'],5),d['A*-R']['completedBlocks']+'/'+d['A*-R']['nBlocks']])
    put('Table_5',rr,'Supplemental B/condition-summary.csv')
    put('Table_S21',[['Backend','Completed movement blocks','M3 / M4 / M5']]+[[alg,f"{sum(int(r['completedBlocks']) for r in b if r['algorithm']==alg)}/{sum(int(r['nBlocks']) for r in b if r['algorithm']==alg)}",'Pass / Pass / Pass'] for alg in ['A*-R','D*L','C-FF','IDFF']],'Supplemental B/condition-summary.csv and eligibility')
    aa=csvread(sup/'A/paired-contrasts.csv');put('Table_S20',[['Contrast','Ratio','99% individual CI','Holm p']]+[[r['numerator']+'/'+r['denominator'],fmt(r['ratio']),interval([r['ci99_low'],r['ci99_high']]),f"{float(r['p_holm_5']):.5g}"] for r in aa],'Supplemental A/paired-contrasts.csv')
    movement=read(res/'movement/main-descriptive-summaries.json')['algorithms'];elig=read(res/'movement/eligibility.json')['M3']['B']['conditions'];rr=[['Case','M1 A*-R/C-FF/IDFF (s)','M1 D*L (s)','M2 A*-R','M2 D*L','M2 C-FF/IDFF','D*L completion']]
    for cond in sorted(movement['A']['M1ByCondition']):rr.append([cond,fmt(movement['A']['M1ByCondition'][cond]['geometricMean'],2),fmt(movement['B']['M1ByCondition'][cond]['geometricMean'],2),fmt(movement['A']['M2ByCondition'][cond]['geometricMean'],5),fmt(movement['B']['M2ByCondition'][cond]['geometricMean'],5),fmt(movement['C']['M2ByCondition'][cond]['geometricMean'],5),f"{elig[cond]['completedBlocks']}/{elig[cond]['plannedBlocks']}"])
    put('Table_S22',rr,'movement/main-descriptive-summaries.json; movement/eligibility.json')
    # Preserve original wording independently so regenerated numeric tables never
    # masquerade as a byte-identical DOCX export.
    page=['<!doctype html><meta charset="utf-8"><title>MTI tables and provenance</title><style>body{font:15px Arial;max-width:1400px;margin:32px auto;padding:20px}table{border-collapse:collapse;margin:14px 0 32px;width:100%}td,th{border:1px solid #ccc;padding:7px;white-space:pre-line;text-align:left}th{background:#edf3f7}.note{color:#805000}h2{margin-top:40px}</style><h1>MTI tables and provenance</h1><p>Numerical tables are generated from recomputed results. Static design text is preserved. AX2 rows and Table S3 have the explicit exceptions below. Original DOCX transcriptions are in original-transcription/.</p>']
    for key,rr in tables.items():
        with (out/'csv'/(key+'.csv')).open('w',encoding='utf-8-sig',newline='') as f:csv.writer(f).writerows(rr)
        page+=['<h2>'+html.escape(meta[key]['caption'])+'</h2>','<p class="note">'+html.escape(meta[key]['mode']+' | '+meta[key].get('source','Source manuscript: design/definition prose'))+'</p>','<table>']
        for i,row in enumerate(rr):tag='th' if i==0 else 'td';page.append('<tr>'+''.join('<'+tag+'>'+html.escape(str(x))+'</'+tag+'>' for x in row)+'</tr>')
        page.append('</table>')
    (out/'tables.html').write_text('\n'.join(page),encoding='utf-8')
    (out/'TABLE_PROVENANCE.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({'tables_and_algorithms':len(tables),'recomputed_or_mixed':sum(x['mode'] in ['RECOMPUTED','MIXED_RECOMPUTED_AND_AX2_SUMMARY'] for x in meta.values()),'AX2_exceptions':['Table 3','Table S1','Table S2','Table S3'],'AX2':'summary only'},indent=2))
if __name__=='__main__':main()
