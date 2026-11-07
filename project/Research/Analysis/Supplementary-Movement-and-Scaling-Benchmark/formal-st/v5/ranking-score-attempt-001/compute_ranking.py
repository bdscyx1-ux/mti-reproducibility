from __future__ import annotations
import csv
import hashlib
import itertools
import json
import math
from datetime import datetime, timezone
from pathlib import Path
from statistics import NormalDist

import numpy as np

ROOT = Path(__file__).resolve().parent
SOURCE = ROOT.parent / 'attempt-004'
ADDENDUM = ROOT.parent / 'attempt-004-reporting-addendum-001'
ALGS = ['A*-R', 'BiA*-R', 'D*L', 'LPA*', 'C-FF', 'IDFF']
DOMAINS = ['D1','D2','D3','D4','D5','D6','D7']
EPS = ['D1 GM','D1 P95','D2','D3','D4','D5','D6','D7']
MODELS = ['D1_GEOMETRIC_MEAN','D1_NEAREST_RANK_P95','D2','D3','D4']
EXPECTED_CONTRACT = 'c8a56bcf2a2d8e68a26b63db6d59cab7389201b32c6d85343b76b28700851660'


def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p): return json.loads(p.read_text('utf-8-sig'))
def write(p, obj): p.write_text(json.dumps(obj, ensure_ascii=False, indent=2)+'\n',encoding='utf-8')
def csvwrite(p, rows):
    with p.open('w',encoding='utf-8-sig',newline='') as f:
        w=csv.DictWriter(f,fieldnames=list(rows[0])); w.writeheader(); w.writerows(rows)


def ranks(v):
    out=np.zeros(len(v),dtype=float)
    remaining=sorted(range(len(v)),key=lambda i:v[i])
    position=1
    while remaining:
        first=remaining[0]
        group=[i for i in remaining if math.isclose(float(v[i]),float(v[first]),rel_tol=1e-10,abs_tol=1e-10)]
        out[group]=position+(len(group)-1)/2
        position+=len(group)
        remaining=[i for i in remaining if i not in group]
    return out


def winners(scores):
    return [ALGS[i] for i in range(6) if math.isclose(float(scores[i]),float(max(scores)),abs_tol=1e-10,rel_tol=1e-10)]


def main():
    assert sha(ROOT/'ranking-contract.v1.json') == EXPECTED_CONTRACT
    contract=read(ROOT/'ranking-contract.v1.json')
    verified=[]
    for folder in [SOURCE,ADDENDUM]:
        for line in (folder/'file-manifest.v1.jsonl').read_text('utf-8-sig').splitlines():
            r=json.loads(line); p=folder/r['relativePath']
            assert sha(p)==r['sha256'] and p.stat().st_size==r['bytes'],str(p)
            verified.append({'source':str(p),'sha256':r['sha256'],'bytes':r['bytes']})
    gates=read(SOURCE/'hard-gates.v1.json')
    assert all(v is True for k,v in gates.items() if k!='schema')
    diag=read(SOURCE/'model-fit-diagnostics.v1.json')
    pairs=read(SOURCE/'exploratory-pair-matrices.v1.json')
    w=np.array([contract['primaryWeights'][d] for d in DOMAINS]); assert np.isclose(w.sum(),1)
    values=np.zeros((6,8)); natural=np.zeros((6,8))
    for j,model in enumerate(MODELS):
        co=diag['models'][model]['coefficients']
        for i,a in enumerate(ALGS):
            values[i,j]=co['Intercept']+co.get(f'algorithm[{a}]',0)
            natural[i,j]=math.expm1(values[i,j]) if model in ['D3','D4'] else math.exp(values[i,j])
    co=diag['models']['D1_GEOMETRIC_MEAN']['coefficients']
    for j,axis in enumerate(['centeredLog2N','centeredLog2F','centeredLog2G2'],5):
        for i,a in enumerate(ALGS):
            values[i,j]=co[axis]+co.get(f'algorithm[{a}]:{axis}',0)
            natural[i,j]=values[i,j]
    point_ranks=np.column_stack([ranks(values[:,j]) for j in range(8)])
    point_utility=100*(6-point_ranks)/5
    utility=np.column_stack([point_utility[:,:2].mean(axis=1),point_utility[:,2:]])
    scores=utility@w

    zcrit=NormalDist().inv_cdf(1-.05/(2*120))
    effects=[]; composites=[]
    for domain in pairs['domains']:
        d=domain['domainId'].split('_')[0]
        for p in domain['pairs']:
            i,k=ALGS.index(p['first']),ALGS.index(p['second'])
            components=[('D1 GM',p['components']['equalDesignGeometricMeanRatio']),('D1 P95',p['components']['equalDesignNearestRankP95Ratio'])] if d=='D1' else [(d,p['component'])]
            rows=[]
            for ep,c in components:
                j=EPS.index(ep); est=c['estimateModelScale']; se=c['standardError']
                assert math.isclose(values[i,j]-values[k,j],est,abs_tol=1e-11)
                assert se>0 and math.isfinite(se)
                lower,upper=est-zcrit*se,est+zcrit*se
                pv=math.erfc(abs(est/se)/math.sqrt(2))
                assert math.isclose(pv,c['twoSidedP'],abs_tol=1e-12,rel_tol=1e-8)
                rows.append({'domain':d,'endpoint':ep,'first':p['first'],'second':p['second'],
                    'differenceModelScale':est,'standardError':se,'z':est/se,
                    'globalSimultaneousLowerModelScale':lower,'globalSimultaneousUpperModelScale':upper,
                    'effect':math.exp(est) if j<5 else est,
                    'globalSimultaneousLower':math.exp(lower) if j<5 else lower,
                    'globalSimultaneousUpper':math.exp(upper) if j<5 else upper,
                    'effectScale':'ratio' if j<5 else 'slope difference per log2 axis unit',
                    'twoSidedP':pv,'globalPrimitiveFamilySize':120})
            comp={'domain':d,'first':p['first'],'second':p['second'],
                  'rawCompositeTwoSidedP':max(r['twoSidedP'] for r in rows),
                  'firstAllComponentsLower':all(r['globalSimultaneousUpperModelScale']<0 for r in rows),
                  'secondAllComponentsLower':all(r['globalSimultaneousLowerModelScale']>0 for r in rows)}
            composites.append(comp); effects.extend(rows)
    assert len(effects)==120 and len(composites)==105
    order=sorted(range(105),key=lambda i:composites[i]['rawCompositeTwoSidedP'])
    running=0
    for j,i in enumerate(order):
        running=max(running,(105-j)*composites[i]['rawCompositeTwoSidedP'])
        composites[i]['globalHolmTwoSidedP']=min(1,running)
    for c in composites:
        c['supportedWinner']=c['first'] if c['firstAllComponentsLower'] and c['globalHolmTwoSidedP']<.05 else c['second'] if c['secondAllComponentsLower'] and c['globalHolmTwoSidedP']<.05 else ''
    for r in effects:
        c=next(c for c in composites if all(c[k]==r[k] for k in ['domain','first','second']))
        r['globalHolmCompositeP']=c['globalHolmTwoSidedP'];r['supportedCompositeWinner']=c['supportedWinner']

    best=np.ones((6,8)); worst=np.full((6,8),6.)
    for r in effects:
        i,k=ALGS.index(r['first']),ALGS.index(r['second']); j=EPS.index(r['endpoint'])
        if r['globalSimultaneousUpperModelScale']<0:
            worst[i,j]-=1;best[k,j]+=1
        elif r['globalSimultaneousLowerModelScale']>0:
            worst[k,j]-=1;best[i,j]+=1
    assert np.all(best<=point_ranks) and np.all(point_ranks<=worst)
    lo_u=100*(6-worst)/5; hi_u=100*(6-best)/5
    lower=np.column_stack([lo_u[:,:2].mean(axis=1),lo_u[:,2:]])@w
    upper=np.column_stack([hi_u[:,:2].mean(axis=1),hi_u[:,2:]])@w
    order_rank=ranks(-scores)
    score_rows=[{'algorithm':a,'rank':order_rank[i],'primaryScore':scores[i],
                 'conservativeSimultaneousScoreLower':lower[i],'conservativeSimultaneousScoreUpper':upper[i],
                 **{d+'Utility':utility[i,j] for j,d in enumerate(DOMAINS)},
                 **{d+'WeightedContribution':utility[i,j]*w[j] for j,d in enumerate(DOMAINS)}} for i,a in enumerate(ALGS)]
    score_rows.sort(key=lambda r:r['rank'])
    input_rows=[{'algorithm':a,'endpoint':e,'domain':e[:2],'modelScaleValue':values[i,j],
                 'referenceAdjustedOriginalScaleOrSlope':natural[i,j],
                 'unit': ['ms','ms','calls','bytes','bytes','log latency per log2 N','log latency per log2 F','log latency per log2 G2'][j],
                 'pointRank':point_ranks[i,j],'rankBestSimultaneous':best[i,j],'rankWorstSimultaneous':worst[i,j],
                 'utility':point_utility[i,j]} for i,a in enumerate(ALGS) for j,e in enumerate(EPS)]
    domain_rows=[]
    for d in DOMAINS:
        for a in ALGS:
            other=[c for c in composites if c['domain']==d and a in [c['first'],c['second']]]
            win=sum(c['supportedWinner']==a for c in other)
            loss=sum(bool(c['supportedWinner']) and c['supportedWinner']!=a for c in other)
            domain_rows.append({'domain':d,'algorithm':a,'supportedWins':win,'supportedLosses':loss,
                               'unresolvedOrTradeoff':5-win-loss,'uniqueDomainWinner':win==5})
    primary=winners(scores)
    separated=[a for i,a in enumerate(ALGS) if all(lower[i]>upper[k]+1e-10 for k in range(6) if k!=i)]
    dominance=[a for a in ALGS if all(r['uniqueDomainWinner'] for r in domain_rows if r['algorithm']==a)]

    # Deterministic preference sensitivity; no simulation of experimental replicates.
    equal=utility.mean(axis=1)
    rho_rows=[]
    runtime=utility[:,:3]@np.array([.5,2/7,3/14]); other=utility[:,3:].mean(axis=1)
    for rho in np.linspace(0,1,201):
        s=rho*runtime+(1-rho)*other
        rho_rows.append({'runtimeGroupWeight':float(rho),**dict(zip(ALGS,s)),'winners':'|'.join(winners(s))})
    boundaries=[0.,1.]
    for i,k in itertools.combinations(range(6),2):
        intercept=other[i]-other[k]; slope=(runtime[i]-other[i])-(runtime[k]-other[k])
        if abs(slope)>1e-12:
            x=-intercept/slope
            if 0<x<1: boundaries.append(float(x))
    boundaries=sorted(set(boundaries)); segments=[]
    for l,u in zip(boundaries,boundaries[1:]):
        who=winners((l+u)/2*runtime+(1-(l+u)/2)*other)
        if segments and segments[-1]['winners']==who:
            segments[-1]['to']=u
        else: segments.append({'from':l,'to':u,'winners':who})
    corners=[]
    for idx,multipliers in enumerate(itertools.product([.5,1.5],repeat=7)):
        ww=w*np.array(multipliers); ww/=ww.sum(); s=utility@ww
        corners.append({'scenario':idx,**{d+'Weight':ww[j] for j,d in enumerate(DOMAINS)},
                        **dict(zip(ALGS,s)),'winners':'|'.join(winners(s))})
    leave=[]
    for j,d in enumerate(DOMAINS):
        ww=w.copy();ww[j]=0;ww/=ww.sum();s=utility@ww
        leave.append({'removedDomain':d,**dict(zip(ALGS,s)),'winners':'|'.join(winners(s))})
    sensitivity={
        'equalWeights':{'winners':winners(equal),'scores':dict(zip(ALGS,equal))},
        'runtimeGroupSweepWinningSegments':segments,
        'runtimeGroupSweepBoundaryWinners':[{'rho':b,'winners':winners(b*runtime+(1-b)*other)} for b in sorted(set([x['from'] for x in segments]+[x['to'] for x in segments]))],
        'weightCornerScenarioCount':128,
        'cornerWinCounts':{a:sum(a in r['winners'].split('|') for r in corners) for a in ALGS},
        'cornerScoreRanges':{a:[min(r[a] for r in corners),max(r[a] for r in corners)] for a in ALGS},
        'leaveOneDomainOut':leave,
        'scenarioFractionsAreNotProbabilities':True}
    result={'schema':'gate14re-me-ranking-score-results-v1','status':'PASS_RANKING_SCORE_ANALYSIS',
            'createdAtUtc':datetime.now(timezone.utc).isoformat(),'contractSha256':EXPECTED_CONTRACT,
            'independentSuperblocks':1296,'algorithmLanes':7776,'eligibilityAllAlgorithms':True,
            'primaryWeights':dict(zip(DOMAINS,w)),'normalization':contract['normalization'],
            'primaryScoreWinners':primary,'statisticallySeparatedScoreWinners':separated,
            'globalDominanceWinners':dominance,'ranking':score_rows,
            'uniqueDomainWinners':{d:[r['algorithm'] for r in domain_rows if r['domain']==d and r['uniqueDomainWinner']] for d in DOMAINS},
            'scoreBoundsMethod':'Conservative projection of all 120 globally simultaneous normal-z ordering intervals; not a bootstrap percentile interval',
            'normalZCritical':zcrit,'primitiveFamilySize':120,'compositeHolmFamilySize':105,
            'sensitivity':sensitivity,'modelRefit':False,'sourceMutation':False,'originalDomainDecisionModified':False}
    write(ROOT/'ranking-results.v1.json',result)
    write(ROOT/'source-verification.v1.json',{'status':'PASS','files':verified,'contractSha256':EXPECTED_CONTRACT})
    csvwrite(ROOT/'score-inputs-and-ranks.v1.csv',input_rows)
    csvwrite(ROOT/'ranking-and-score-contributions.v1.csv',score_rows)
    csvwrite(ROOT/'all-pair-primitive-inference.v1.csv',effects)
    csvwrite(ROOT/'all-pair-composite-decisions.v1.csv',composites)
    csvwrite(ROOT/'domain-winner-decisions.v1.csv',domain_rows)
    csvwrite(ROOT/'runtime-weight-sensitivity.v1.csv',rho_rows)
    csvwrite(ROOT/'weight-corner-sensitivity.v1.csv',corners)
    csvwrite(ROOT/'leave-one-domain-out.v1.csv',leave)
    # Confirm file-bound sources were not changed by the new analysis.
    assert all(sha(Path(r['source']))==r['sha256'] for r in verified)
    print(json.dumps({'ranking':score_rows,'primaryWinner':primary,'separatedScoreWinner':separated,
                      'domainWinners':result['uniqueDomainWinners'],'sensitivity':sensitivity},ensure_ascii=False,indent=2))


if __name__=='__main__': main()
