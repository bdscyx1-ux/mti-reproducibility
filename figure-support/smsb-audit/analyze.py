"""Additional diagnostics only; original acquisition and analyses remain immutable."""
from pathlib import Path
import json,hashlib,importlib.util,math,itertools,datetime,sys
import numpy as np
import pandas as pd
ROOT=Path(__file__).resolve().parent;SRC=ROOT/'source';OUT=ROOT/'analysis';OUT.mkdir(exist_ok=True)
def load(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def save(n,d):(OUT/n).write_text(json.dumps(d,ensure_ascii=False,indent=2,allow_nan=False),encoding='utf-8')
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
for item in load(ROOT/'source_manifest.json'):assert digest(ROOT/item['packaged'])==item['sha256']
assert digest(ROOT/'PROTOCOL.md')==load(ROOT/'protocol_freeze.json')['sha256']
spec=importlib.util.spec_from_file_location('archived_analysis',SRC/'gate14re_me_formal_st_analysis_v1_3.py');archived=importlib.util.module_from_spec(spec);spec.loader.exec_module(archived)
data=pd.read_json(SRC/'lane-estimands.v1.jsonl',lines=True).sort_values(['superblockId','algorithm']).reset_index(drop=True)
assert len(data)==7776 and data.groupby('superblockId').size().eq(6).all() and not data.duplicated(['superblockId','algorithm']).any()
assert data.superblockId.nunique()==1296
assert data.groupby(['gridEdge','agentCount','changedCellCount']).superblockId.nunique().eq(36).all()
lanes=data.to_dict(orient='records');X,columns,indices,centers=archived.build_design_matrix(lanes)
diag=load(SRC/'model-fit-diagnostics.v1.json');assert columns==diag['fixedEffectColumns']
N,P=X.shape;G=1296;m=6;df=G-1;groups=[np.asarray(v) for v in data.groupby('superblockId',sort=True).indices.values()]
Xg=X.reshape(G,m,P);cluster_names=data.superblockId.iloc[::6].to_numpy()
t95=archived.t_ppf(.975,df);t99=archived.t_ppf(.995,df);factor=G/(G-1)*(N-1)/(N-P)
outcomes={'D1_GEOMETRIC_MEAN':('d1GeometricMeanMilliseconds','log'),'D1_NEAREST_RANK_P95':('d1NearestRankP95Milliseconds','log'),'D2':('d2GridAccessorCalls','log'),'D3':('d3TotalManagedAllocationBytes','log1p'),'D4':('d4MaxPersistentStateBytes','log1p')}
robust=[];residual_frames=[];reconstruction=[];byalgo=[];bycell=[];pair_matrix=[];cellrows=[];equivalence=[]
for name,(col,transform) in outcomes.items():
    y=(np.log1p if transform=='log1p' else np.log)(data[col].to_numpy(dtype=float));yg=y.reshape(G,m)
    model=diag['models'][name];beta=np.asarray([model['coefficients'][c] for c in columns]);var=model['variance'];sigma=var['residual'];tau=var['superblockRandomIntercept']
    Vi=(np.eye(m)-tau/(sigma+m*tau)*np.ones((m,m)))/sigma
    info=np.einsum('gmi,mn,gnj->ij',Xg,Vi,Xg);bread=np.linalg.inv(info)
    rhs=np.einsum('gmi,mn,gn->i',Xg,Vi,yg);rebeta=np.linalg.solve(info,rhs)
    delta=float(np.max(np.abs(rebeta-beta)));assert delta<1e-8,(name,delta)
    reconstruction.append({'outcome':name,'max_abs_beta_difference':delta,'rank':int(np.linalg.matrix_rank(X))})
    e=y-X@beta;eg=e.reshape(G,m);blup=tau/(sigma+m*tau)*eg.sum(axis=1);conditional=eg-blup[:,None]
    scores=np.einsum('gmi,mn,gn->gi',Xg,Vi,eg);cov=factor*bread@(scores.T@scores)@bread
    contrast=archived.algorithm_contrast(indices,'IDFF','C-FF');estimate=float(contrast@beta);se=math.sqrt(float(contrast@cov@contrast))
    # info is X'V^-1X with actual sigma, so frozen model covariance equals inv(info).
    modelse=math.sqrt(float(contrast@bread@contrast))
    log95=[estimate-t95*se,estimate+t95*se];log99=[estimate-t99*se,estimate+t99*se]
    robust.append({'outcome':name,'numerator':'IDFF','denominator':'C-FF','transform':transform,'log_contrast':estimate,'ratio':math.exp(estimate),'model_se':modelse,'cluster_cr1_se':se,'cr1_to_model_se_ratio':se/modelse,'ratio_ci95_pointwise':np.exp(log95).tolist(),'ratio_ci99_bonferroni_five':np.exp(log99).tolist(),'df':df,'clusters':G,'cr1_factor':factor,'point_estimate_preserved':True,'plug_in_variance_parameters':True})
    frame=data[['superblockId','algorithm','gridEdge','agentCount','changedCellCount','contextStratumId','executionPosition']].copy();frame['outcome']=name;frame['transformed_y']=y;frame['fitted_fixed']=X@beta;frame['random_intercept_blup']=np.repeat(blup,m);frame['marginal_residual']=e;frame['conditional_residual']=conditional.ravel();residual_frames.append(frame)
    def summarize(keys,dest):
        for key,part in frame.groupby(keys,sort=True):
            if not isinstance(key,tuple):key=(key,)
            r={'outcome':name,**dict(zip(keys,key)),'n':len(part)}
            for typ in ['marginal','conditional']:
                a=part[typ+'_residual'].to_numpy();r.update({typ+'_mean':float(a.mean()),typ+'_sd':float(a.std(ddof=1)),typ+'_rmse':float(np.sqrt(np.mean(a*a))),typ+'_abs_p95':float(np.quantile(np.abs(a),.95))})
            dest.append(r)
    summarize(['algorithm'],byalgo);summarize(['algorithm','gridEdge','agentCount','changedCellCount'],bycell)
    pair=data[['superblockId','algorithm','gridEdge','agentCount','changedCellCount',col]].copy();pair['y']=y
    pivot=pair.pivot(index='superblockId',columns='algorithm',values='y').reindex(cluster_names)
    differences=(pivot['IDFF']-pivot['C-FF']).to_numpy();pair_matrix.append(differences)
    pair['transformed_difference']=pair.superblockId.map(dict(zip(cluster_names,differences)))
    for key,part in pair[pair.algorithm=='IDFF'].groupby(['gridEdge','agentCount','changedCellCount']):cellrows.append({'outcome':name,'gridEdge':key[0],'agentCount':key[1],'changedCellCount':key[2],'blocks':len(part),'paired_ratio':float(np.exp(part.transformed_difference.mean()))})
    p=data.pivot(index='superblockId',columns='algorithm',values=col)
    equivalence.append({'outcome':name,'DStar_LPA_exact_equal_blocks':int(p['D*L'].eq(p['LPA*']).sum()),'blocks':G,'paired_log_difference_correlation_not_used_as_replication':True})
pd.concat(residual_frames).to_csv(OUT/'residuals_all_lanes.csv',index=False)
pd.DataFrame(byalgo).to_csv(OUT/'residuals_by_algorithm.csv',index=False);pd.DataFrame(bycell).to_csv(OUT/'residuals_by_algorithm_cell.csv',index=False);pd.DataFrame(cellrows).to_csv(OUT/'paired_cell_ratios.csv',index=False)
save('cluster_robust_reference_contrasts.json',robust);save('coefficient_reconstruction.json',reconstruction)
# All outcomes share the same block bootstrap draws. One block contains all six lanes.
block_meta=data.iloc[::6][['superblockId','gridEdge','agentCount','changedCellCount']].reset_index(drop=True)
cell_indices=[v.to_numpy() for _,v in block_meta.groupby(['gridEdge','agentCount','changedCellCount']).groups.items()]
assert len(cell_indices)==36 and all(len(x)==36 for x in cell_indices)
arr=np.column_stack(pair_matrix);rng=np.random.default_rng(20261103);samples=np.zeros((5000,len(outcomes)))
for ids in cell_indices:
    draw=rng.integers(0,36,size=(5000,36));samples+=arr[ids[draw]].mean(axis=1)/36
paired=[]
for j,name in enumerate(outcomes):
    sub=[r['paired_ratio'] for r in cellrows if r['outcome']==name]
    paired.append({'outcome':name,'ratio':float(np.exp(arr[:,j].mean())),'ratio_ci95_percentile':np.exp(np.quantile(samples[:,j],[.025,.975])).tolist(),'cell_ratio_min':min(sub),'cell_ratio_max':max(sub),'cells_below_one':sum(x<1 for x in sub),'clusters':1296,'bootstrap_draws':5000,'resampling':'complete six-lane blocks within 36 G/N/F cells','estimand':'workload-average paired transformed difference, not the adjusted reference predictor','shifted_ratio':outcomes[name][1]=='log1p'})
save('paired_block_bootstrap.json',paired)
# Rank scores do not become effect sizes. Preserve and verify original utilities.
inputs=pd.read_csv(SRC/'score-inputs-and-ranks.v1.csv');results=load(SRC/'ranking-results.v1.json');algorithms=['A*-R','BiA*-R','D*L','LPA*','C-FF','IDFF'];domains=[f'D{i}' for i in range(1,8)]
utility=inputs.groupby(['algorithm','domain']).utility.mean().unstack().reindex(index=algorithms,columns=domains)
weights={'original':np.array([.35,.20,.15,.075,.075,.075,.075]),'equal':np.ones(7)/7,'latency_priority':np.array([.70,.10,.05,.05,.04,.03,.03]),'retained_state_priority':np.array([.10,.05,.05,.60,.05,.05,.10])}
schemes=[];scheme_summary=[]
for name,w in weights.items():
    assert abs(w.sum()-1)<1e-12;scores=utility.to_numpy()@w;ranks=pd.Series(scores).rank(ascending=False,method='min').to_numpy();winners=[a for a,s in zip(algorithms,scores) if abs(s-max(scores))<1e-9]
    scheme_summary.append({'scheme':name,'weights':dict(zip(domains,w.tolist())),'point_winners':winners})
    for a,s,r in zip(algorithms,scores,ranks):schemes.append({'scheme':name,'algorithm':a,'score':float(s),'point_rank':int(r),'winner':a in winners})
    if name=='original':
        prior={r['algorithm']:r['primaryScore'] for r in results['ranking']};assert all(abs(prior[a]-s)<1e-10 for a,s in zip(algorithms,scores))
pd.DataFrame(schemes).to_csv(OUT/'weight_scenarios.csv',index=False)
def compositions(total,k,prefix=()):
    if k==1:yield prefix+(total,)
    else:
        for i in range(total+1):yield from compositions(total-i,k-1,prefix+(i,))
simplex=np.asarray(list(compositions(10,7)),dtype=float)/10;assert simplex.shape==(8008,7)
score_matrix=simplex@utility.to_numpy().T;winning=np.abs(score_matrix-score_matrix.max(axis=1)[:,None])<1e-9
single=winning.sum(axis=1)==1
counts=[{'algorithm':a,'unique_top_count':int((winning[:,i]&single).sum()),'co_top_count_including_ties':int(winning[:,i].sum()),'scenarios':8008} for i,a in enumerate(algorithms)]
scan=pd.DataFrame(simplex,columns=[x+'_weight' for x in domains]);scan[[a+'_score' for a in algorithms]]=score_matrix;scan['point_winners']=[';'.join(a for a,v in zip(algorithms,row) if v) for row in winning];scan.to_csv(OUT/'simplex_weight_scan.csv',index=False)
weight_summary={'scheme_summaries':scheme_summary,'simplex_grid_step':.1,'simplex_vectors':8008,'tie_vectors':int((~single).sum()),'winner_counts':counts,'counts_are_probabilities':False,'statistically_separated_winner_recomputed':False,'archived_primary_score_intervals':[{k:v for k,v in r.items() if k in ['algorithm','primaryScore','conservativeSimultaneousScoreLower','conservativeSimultaneousScoreUpper']} for r in results['ranking']],'archived_sensitivity':results['sensitivity']}
save('weight_sensitivity_summary.json',weight_summary)
effect=[]
for endpoint,frame in inputs.groupby('endpoint',sort=False):
    lookup=frame.set_index('algorithm');a=lookup.loc['IDFF'];b=lookup.loc['C-FF'];slope=endpoint in ['D5','D6','D7']
    effect.append({'endpoint':endpoint,'IDFF_reference_value_or_slope':float(a.referenceAdjustedOriginalScaleOrSlope),'CFF_reference_value_or_slope':float(b.referenceAdjustedOriginalScaleOrSlope),'unit':a.unit,'IDFF_minus_CFF_model_scale':float(a.modelScaleValue-b.modelScaleValue),'ratio_interpretation':'relative per-axis latency multiplier' if slope else ('shifted +1 ratio' if endpoint in ['D3','D4'] else 'ratio'),'exp_model_difference':float(math.exp(a.modelScaleValue-b.modelScaleValue)),'unshifted_reference_ratio_not_inferential':None if slope else float(a.referenceAdjustedOriginalScaleOrSlope/b.referenceAdjustedOriginalScaleOrSlope),'IDFF_per_log2_unit_multiplier':float(math.exp(a.modelScaleValue)) if slope else None,'CFF_per_log2_unit_multiplier':float(math.exp(b.modelScaleValue)) if slope else None})
pd.DataFrame(effect).to_csv(OUT/'effect_size_idff_cff.csv',index=False)
save('related_implementation_resource_equality.json',equivalence)
spread=[]
for outcome in outcomes:
    aa=[r for r in byalgo if r['outcome']==outcome];cc=[r for r in bycell if r['outcome']==outcome]
    sd=[r['conditional_sd'] for r in aa];cs=[r['conditional_sd'] for r in cc]
    spread.append({'outcome':outcome,'algorithm_conditional_sd_min':min(sd),'algorithm_conditional_sd_max':max(sd),'algorithm_sd_max_over_min':max(sd)/min(sd),'algorithm_cell_conditional_sd_min':min(cs),'algorithm_cell_conditional_sd_max':max(cs),'algorithm_cell_count':216})
summary={'status':'completed_additional_diagnostics','utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'superblocks':1296,'lanes':7776,'design_columns':34,'coefficient_reconstruction':reconstruction,'robust_reference_contrasts':robust,'paired_bootstrap':paired,'residual_spread':spread,'weight_sensitivity':weight_summary,'effect_sizes':effect,'related_implementation_equality':equivalence,'original_analysis_overwritten':False,'new_map_or_machine_replication':False}
save('summary.json',summary)
(OUT/'SUCCESS.json').write_text(json.dumps({'status':'PASS_EXECUTION_AND_SOURCE_IDENTITY','superblocks':1296,'lanes':7776,'models':5,'simplex_vectors':8008},indent=2))
print(json.dumps({'status':'completed','contrasts':robust,'residual_spread':spread,'weight_schemes':scheme_summary,'simplex_counts':counts},indent=2))
