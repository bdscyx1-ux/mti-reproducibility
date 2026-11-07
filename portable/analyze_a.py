from pathlib import Path
import json,hashlib,math,statistics,csv,datetime,sys
from portable_paths import configuration, resolve_recorded_path
ARGS=configuration()
ROOT=ARGS.input_root
OUTPUT=ARGS.output_root
def relocated(value): return resolve_recorded_path(value, ROOT)
def load(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def sha(p):
 with open(p,'rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def holm(p):
 out=[0.0]*len(p);running=0
 for n,i in enumerate(sorted(range(len(p)),key=lambda i:p[i])):
  running=max(running,min(1,(len(p)-n)*p[i]));out[i]=running
 return out
def main():
 jobs=load(ROOT/'A-jobs.json');assert len(jobs)==1536
 cases={};rows=[];files=[]
 ids=['A*-R','D*L','C-FF','IDFF'];totals={a:{k:0 for k in ['planOperationCount','succeededPlanCount','noPathPlanCount','invalidPlanCount','failedPlanCount','budgetExceededPlanCount']} for a in ids}
 status_mismatches=[]
 for j in jobs:
  folder=relocated(j['output']);p=folder/'block-result.json';r=load(folder/'process-receipt.json');x=load(p)
  assert r['passed'] and r['exitCode']==0 and r['outputSha256']==sha(p)
  assert sha(relocated(j['plan']))==j['planSha256']
  assert x['studyId']=='DDM-Revision-20261103-A' and x['completed'] and x['planSha256']==j['planSha256'] and x['scenarioId']==j['scenarioId'] and x['blockIndex']==j['blockIndex']
  assert [s['algorithmId'] for s in x['samples']]==load(relocated(j['plan']))['algorithms']
  samples={s['algorithmId']:s for s in x['samples']};assert len(samples)==4
  values={a:samples[a]['dynamicHandlingMillisecondsPerScheduledEvent'] for a in ids};assert all(v>0 and math.isfinite(v) for v in values.values())
  cases.setdefault(j['scenarioId'],{})[j['blockIndex']]=values
  reference=(samples['A*-R']['succeededPlanCount'],samples['A*-R']['noPathPlanCount'])
  for a,s in samples.items():
   rows.append({'scenario':j['scenarioId'],'block':j['blockIndex'],'algorithm':a,'P1_ms_per_event':values[a],**{k:s[k] for k in totals[a]}})
   for k in totals[a]:totals[a][k]+=s[k]
   if (s['succeededPlanCount'],s['noPathPlanCount'])!=reference:status_mismatches.append({'scenario':j['scenarioId'],'block':j['blockIndex'],'algorithm':a})
  files.append({'path':str(p),'sha256':r['outputSha256']})
 assert len(cases)==32 and all(set(v)==set(range(1,49)) for v in cases.values())
 contrasts=[];pairs=[('C-FF','A*-R'),('C-FF','D*L'),('IDFF','A*-R'),('IDFF','D*L'),('IDFF','C-FF')]
 z=statistics.NormalDist().inv_cdf(.995)
 for a,b in pairs:
  means=[statistics.mean(math.log(v[a]/v[b]) for v in blocks.values()) for blocks in cases.values()]
  m=statistics.mean(means);se=statistics.stdev(means)/math.sqrt(32)
  two=math.erfc(abs(m/se)/math.sqrt(2)) if se>0 else (1.0 if m==0 else 0.0)
  directional=0.5*math.erfc(-m/se/math.sqrt(2)) if se>0 else (0.0 if m<0 else 1.0)
  p=two if (a,b)==('IDFF','C-FF') else directional
  contrasts.append({'numerator':a,'denominator':b,'ratio':math.exp(m),'ci99_low':math.exp(m-z*se),'ci99_high':math.exp(m+z*se),'logSE':se,'p_unadjusted_prespecified':p,'test_direction':'two-sided' if (a,b)==('IDFF','C-FF') else 'numerator-lower-one-sided','p_two_sided_diagnostic':two})
 for c,p in zip(contrasts,holm([c['p_unadjusted_prespecified'] for c in contrasts])):c['p_holm_5']=p
 gm={a:math.exp(statistics.mean(statistics.mean(math.log(v[a]) for v in blocks.values()) for blocks in cases.values())) for a in ids}
 summary={'studyId':'DDM-Revision-20261103-A','createdUtc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'blocks':1536,'algorithmSamples':6144,'scenarioCount':32,'geometricMeanP1_ms_per_event':gm,'contrasts':contrasts,'statusTotals':totals,'statusCountMismatchesAgainstAStar':status_mismatches,'analysis':'paired block log ratios; equal32campaign weights; normal reference andBonferroni99%individual intervals across5contrasts, Holm5; newacquisitiononly','interpretationBoundary':'fixedscenario matrix and frozenimplementations; failedqueries retainedandreported; nohistoricaltimingpooling','oracleVerification':load(ROOT/'A-oracle-verification.json')['passed']}
 out=OUTPUT/'A';out.mkdir(parents=True,exist_ok=False)
 for name,data in [('summary.json',summary),('input-manifest.json',files)]:
  (out/name).write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')
 for name,data in [('sample-results.csv',rows),('paired-contrasts.csv',contrasts)]:
  with (out/name).open('w',newline='',encoding='utf-8-sig') as f:w=csv.DictWriter(f,fieldnames=list(data[0]));w.writeheader();w.writerows(data)
 lines=['A 共同目标动态规划补充实验结果','新采集32场景×48配对块×4方法，全部6144算法样本已验证。','本报告只使用本次新数据。原始历史数据不合并。','P1为每个计划地形事件的归一化处理毫秒数。']
 lines += [f'{a}: P1几何均值 {gm[a]:.6f} ms/event；成功{totals[a]["succeededPlanCount"]}，无路{totals[a]["noPathPlanCount"]}，失败{totals[a]["failedPlanCount"]}，无效{totals[a]["invalidPlanCount"]}。' for a in ids]
 lines += [f'{c["numerator"]}/{c["denominator"]}: {c["ratio"]:.6f}，同时校正区间[{c["ci99_low"]:.6f}, {c["ci99_high"]:.6f}]，Holm p={c["p_holm_5"]:.6g}。' for c in contrasts]
 lines += [f'与A*成功/无路计数不一致的算法样本数：{len(status_mismatches)}。','置信区间描述本设计中的不确定性，不代表所有地图、硬件或应用场景。','独立最短路检查为单独功能核验，不计入计时样本。']
 (out/'结果说明.txt').write_text('\n'.join(lines),encoding='utf-8');print(str(out))
if __name__=='__main__':main()
