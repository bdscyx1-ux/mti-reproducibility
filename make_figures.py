"""Regenerate all five manuscript figures from recomputed historical results."""
from pathlib import Path
import argparse,csv,json,sys,shutil,hashlib
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.lines import Line2D
from matplotlib.ticker import ScalarFormatter,FuncFormatter,NullFormatter
ROOT=Path(__file__).resolve().parent
from tools.check_figure_layout import require_matplotlib_panel_alignment
ALGS=['A*-R','BiA*-R','D*L','LPA*','C-FF','IDFF']
COLORS=['#777777','#a4a4a4','#4c78a8','#70a3b8','#d98a30','#207b72']
MARKERS=['o','s','^','v','D','P']
plt.rcParams.update({'font.family':'sans-serif','font.sans-serif':['DejaVu Sans'],'font.size':9,'axes.titlesize':10,'axes.labelsize':9,'xtick.labelsize':8,'ytick.labelsize':9,'axes.spines.top':False,'axes.spines.right':False,'pdf.fonttype':42,'ps.fonttype':42,'svg.fonttype':'none','savefig.dpi':300,'axes.linewidth':.8})
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def rows(p):
    with p.open(encoding='utf-8-sig',newline='') as f:return list(csv.DictReader(f))
def csvwrite(p,rr):
    with p.open('w',encoding='utf-8-sig',newline='') as f:
        w=csv.DictWriter(f,fieldnames=list(rr[0]));w.writeheader();w.writerows(rr)
def label(ax,i,title):
    offset=.28/(ax.get_position().width*ax.figure.get_figwidth())
    ax.text(-offset,1.09,chr(97+i),transform=ax.transAxes,fontweight='bold',fontsize=12,va='bottom')
    ax.set_title(title,loc='left',pad=8)
def save(fig,out,name,source,axes=None):
    fig.canvas.draw()
    if len(fig.axes)>1:require_matplotlib_panel_alignment(fig,json_out=out/(name+'.alignment.json'),strict=True,tolerance_pt=1.5)
    fig.savefig(out/(name+'.pdf'))
    fig.savefig(out/(name+'.svg'))
    fig.savefig(out/(name+'.png'),dpi=300)
    csvwrite(out/'source-data'/(name+'.csv'),source)
    plt.close(fig)
def dist(ax,rr,field,i,title,unit):
    for y,a in enumerate(ALGS):
        r=next(r for r in rr if r['algorithm']==a and r['sourceField']==field);c=COLORS[y]
        assert float(r['p05'])>0, 'log-axis input must be positive'
        ax.plot([float(r['p05']),float(r['p95'])],[y,y],color=c,lw=1.3)
        ax.plot([float(r['p25']),float(r['p75'])],[y,y],color=c,lw=5,solid_capstyle='butt')
        ax.plot(float(r['median']),y,MARKERS[y],color=c,mec='white',mew=.6,ms=5)
    ax.set_yticks(range(6),ALGS);ax.set_ylim(5.6,-.6);ax.set_xscale('log');ax.set_xlabel(unit+' (log scale)');ax.grid(axis='x',alpha=.18);label(ax,i,title)
    ax.xaxis.set_major_formatter(FuncFormatter(lambda v,pos:f'{v:g}'));ax.xaxis.set_minor_formatter(NullFormatter())
    if i==4:ax.set_xticks([100,10000,1000000,100000000],['100','10000','1e+06','1e+08'])
def figure1(res,out):
    rr=rows(res/'smsb-reporting/raw-scale-by-algorithm.v1.csv');pr=rows(res/'smsb-reporting/formal-ratio-provenance.v1.csv');c=read(res/'smsb/confirmatory-results.v1.json')
    fig,aa=plt.subplots(3,2,figsize=(7.8,8.7));fig.subplots_adjust(left=.1,right=.98,bottom=.065,top=.94,hspace=.68,wspace=.48)
    specs=[('d1GeometricMeanMilliseconds','D1 Event-group GM','Milliseconds'),('d1NearestRankP95Milliseconds','D1 Event-group P95','Milliseconds'),('d2GridAccessorCalls','D2 Grid-read work','Calls'),('d3TotalManagedAllocationBytes','D3 Dynamic allocation','Bytes'),('d4MaxPersistentStateBytes','D4 Persistent state','Bytes')]
    for i,(field,title,unit) in enumerate(specs):dist(aa.flat[i],rr,field,i,title,unit)
    ax=aa.flat[5];ax.axis('off');label(ax,5,'C-FF P95 comparison traced')
    r=next(r for r in pr if r['sourceField']=='d1NearestRankP95Milliseconds' and r['comparator']=='C-FF')
    h=next(h for h in c['hypotheses'] if h['domainId'].startswith('D1_') and h['comparator']=='C-FF')['components']['equalDesignNearestRankP95Ratio']
    lo,hi=h['simultaneousTwoSidedBonferroniRatioInterval']
    text=f"Observed lane means (ms)\nIDFF {float(r['idffRawMean']):.4f} / C-FF {float(r['comparatorRawMean']):.4f}\nDescriptive mean ratio = {float(r['idffRawMean'])/float(r['comparatorRawMean']):.4f}\n\nModel input: ln(lane P95)\nAdjusted reference values (ms)\nIDFF {float(r['idffReferenceAdjustedRawScale']):.4f} / C-FF {float(r['comparatorReferenceAdjustedRawScale']):.4f}\n\nFormal ratio = {h['ratioEstimate']:.5f}\nSimultaneous CI {lo:.5f}–{hi:.5f}"
    ax.text(0,.97,text,transform=ax.transAxes,va='top',fontsize=8.5,linespacing=1.45)
    src=[{'panel':chr(97+i),**r} for i,(f,_,_) in enumerate(specs) for r in rr if r['sourceField']==f]
    save(fig,out,'Figure_1',src)
    csvwrite(out/'source-data/Figure_1f.csv',[r])
def figure2(res,out):
    hypotheses=read(res/'smsb/confirmatory-results.v1.json')['hypotheses']
    titles=['D1 GM latency ratio','D1 P95 latency ratio','D2 Grid-read ratio','D3 Allocation + 1 ratio','D4 State bytes + 1 ratio','D5 Agent-count slope difference','D6 Footprint slope difference','D7 Grid-area slope difference']
    domains=[1,1,2,3,4,5,6,7];src=[]
    fig,aa=plt.subplots(4,2,figsize=(7.8,9.6));fig.subplots_adjust(left=.1,right=.98,bottom=.09,top=.95,hspace=.78,wspace=.48)
    for i,ax in enumerate(aa.flat):
        for y,a in enumerate(ALGS[:-1]):
            h=next(h for h in hypotheses if h['domainId'].startswith(f'D{domains[i]}_') and h['comparator']==a)
            c=h['components'][['equalDesignGeometricMeanRatio','equalDesignNearestRankP95Ratio'][i]] if i<2 else h['component']
            val=c['ratioEstimate'] if i<5 else c['estimateModelScale'];lo,hi=c['simultaneousTwoSidedBonferroniRatioInterval'] if i<5 else c['simultaneousTwoSidedBonferroniIntervalModelScale']
            passed=bool(h['rejectAtFamilywiseAlpha0.05']);color=COLORS[5] if passed else '#bc7525'
            ax.errorbar(val,y,xerr=[[val-lo],[hi-val]],fmt='o',ms=4.5,color=color,mfc=color if passed else 'white',capsize=2,lw=1.2)
            src.append({'panel':chr(97+i),'comparator':a,'estimate':val,'lower':lo,'upper':hi,'composite_passed':passed,'family_size':40})
        ax.axvline(1 if i<5 else 0,color='#bbbbbb',ls='--',lw=.8);ax.set_yticks(range(5),ALGS[:-1]);ax.set_ylim(4.6,-.6);ax.grid(axis='x',alpha=.18)
        if i<5:
            ax.set_xscale('log');ax.xaxis.set_minor_formatter(NullFormatter())
            ticks=[[.2,.5,1],[.1,.2,.5,1],[.2,.5,1],[.01,.05,.2,1],[.01,1,100,10000]][i]
            ax.set_xticks(ticks,[f'{x:g}' for x in ticks])
        ax.set_xlabel('IDFF / comparator' if i<5 else 'IDFF − comparator');label(ax,i,titles[i])
    handles=[Line2D([],[],marker='o',linestyle='',color=COLORS[5],label='Composite hypothesis passed'),Line2D([],[],marker='o',linestyle='',mfc='white',color='#bc7525',label='Composite hypothesis not passed')]
    fig.legend(handles=handles,loc='lower center',bbox_to_anchor=(.53,.01),ncol=2,frameon=False,fontsize=8)
    save(fig,out,'Figure_2',src)
def figure3(res,out):
    summary=read(res/'mq/descriptive-condition-summaries.v1.json')['rows'];raw=read(res/'mq/batch-wall-time-source.json');contrasts=read(res/'mq/confirmatory-and-secondary-results.v1.json')['results']
    blocks=[json.loads(x) for x in (res/'mq/block-estimands.v1.jsonl').read_text('utf-8').splitlines()]
    fig=plt.figure(figsize=(8.2,7.2));gs=fig.add_gridspec(2,2,left=.23,right=.98,bottom=.1,top=.92,hspace=.65,wspace=.3,height_ratios=[1,1.25]);aa=[fig.add_subplot(gs[0,0]),fig.add_subplot(gs[0,1]),fig.add_subplot(gs[1,:])];src=[]
    # Deterministic display offsets only; measured values are never simulated or changed.
    for i,alg in enumerate(['C-FF','IDFF']):
        ax=aa[i]
        for top,col,mark,offset in [('LARGE-L3','#0085bb','o',-.07),('HIGH-FREQUENCY','#df6e00','s',.07)]:
            xx=[];yy=[]
            for j,w in enumerate([1,2,4,8]):
                cond=f'MQ-{top}-W{w}';r=next(r for r in summary if r['algorithmId']==alg and r['conditionId']==cond)
                values=[r['seconds'] for r in raw if r['algorithm']==alg and r['condition']==cond];assert len(values)==36
                x=j+offset;v=r['geometricMeanBatchWallSeconds'];lo,hi=r['ordinaryTwoSided95CiBatchWallSeconds'];xx.append(x);yy.append(v)
                ax.scatter(x+.025*np.sin(np.arange(len(values))*2.4),values,s=8,c=col,alpha=.2,edgecolors='none')
                ax.errorbar(x,v,yerr=[[v-lo],[hi-v]],color=col,fmt=mark,capsize=2,mec='white',mew=.6,ms=5,lw=1.5)
                src.append({'panel':chr(97+i),'algorithm':alg,'condition':cond,'estimate':v,'lower':lo,'upper':hi,'n':36})
            ax.plot(xx,yy,color=col,lw=1.2)
        ax.set_xticks(range(4),['1','2','4','8']);ax.set_xlabel('Managed worker count');ax.set_yscale('log',base=2);ax.set_ylim(2.5,75);ax.set_yticks([4,8,16,32,64],['4','8','16','32','64']);ax.grid(axis='y',alpha=.3);label(ax,i,alg)
        if i==0:ax.set_ylabel('Batch wall time (s; log₂ scale)')
    fig.legend(handles=[Line2D([],[],color='#0085bb',marker='o',label='Large-L3 single CCD'),Line2D([],[],color='#df6e00',marker='s',label='High-frequency single CCD')],loc='upper center',bbox_to_anchor=(.61,1.0),ncol=2,frameon=False,fontsize=8)
    ax=aa[2];labs=[]
    for i,r in enumerate(contrasts):
        alg=r['algorithmId'];h=r['hypothesisId'];col='#009e82' if alg=='C-FF' else '#80539b';v=r['geometricRatio'];lo,hi=r['ordinaryTwoSided95CiRatio'];vals=[b['geometricRatio'] for b in blocks if b['hypothesisId']==h]
        ax.scatter(vals,i+.12*np.sin(np.arange(len(vals))*2.4),s=9,c=col,alpha=.22,edgecolors='none');ax.errorbar(v,i,xerr=[[v-lo],[hi-v]],fmt='o',color=col,capsize=3,mec='white',mew=.7,ms=5)
        top={'LARGE_L3_CCD':'large-L3 · ×2','HIGH_FREQUENCY_CCD':'high-freq. · ×2'}.get(r['topology'],'dual CCD · 16/8');labs.append(alg+' · '+top)
        ax.text(1.045,i,f'{v:.3f} [{lo:.3f}, {hi:.3f}]',va='center',fontsize=8)
        src.append({'panel':'c','algorithm':alg,'condition':h,'estimate':v,'lower':lo,'upper':hi,'n':36})
    ax.axvline(.9,color='#c84527',ls='--',lw=1);ax.axvline(1,color='#888888',ls=':',lw=1);ax.axhline(3.5,color='#dddddd',lw=.8)
    ax.set_yticks(range(6),labs,fontsize=8);ax.set_ylim(5.55,-.5);ax.set_xlim(.5,1.23);ax.set_xlabel('Batch wall-time ratio (lower is better)');label(ax,2,'Prespecified within-algorithm scaling effects')
    save(fig,out,'Figure_3',src);csvwrite(out/'source-data/Figure_3_raw_batches.csv',raw);csvwrite(out/'source-data/Figure_3_raw_contrasts.csv',blocks)
def figureS1(res,out):
    rr=rows(res/'smsb-reporting/raw-scale-by-axis.v1.csv');fig,aa=plt.subplots(1,3,figsize=(9,3.8));fig.subplots_adjust(left=.075,right=.985,top=.83,bottom=.27,wspace=.37)
    for i,(field,title,xlab) in enumerate([('agentCount','Agent count','N'),('changedCellCount','Change footprint','Changed cells F'),('gridEdge','Grid size','Grid edge G')]):
        ax=aa[i]
        for j,alg in enumerate(ALGS):
            ar=sorted([r for r in rr if r['axisField']==field and r['algorithm']==alg],key=lambda r:float(r['axisLevel']));x=np.array([float(r['axisLevel']) for r in ar]);y=np.array([float(r['median']) for r in ar]);lo=np.array([float(r['p25']) for r in ar]);hi=np.array([float(r['p75']) for r in ar])
            ax.errorbar(x,y,yerr=[y-lo,hi-y],color=COLORS[j],marker=MARKERS[j],linestyle='--' if alg=='LPA*' else '-',ms=4,capsize=2,lw=1,label=alg)
        ax.set_xscale('log');ax.set_yscale('log');ax.set_xticks(x,[str(int(v)) for v in x]);ax.minorticks_off();ax.set_yticks([10,100,1000],['10','100','1000']);ax.set_ylim(5,1000);ax.set_xlabel(xlab);ax.grid(axis='y',alpha=.2);label(ax,i,title)
        if i==0:ax.set_ylabel('Lane GM latency (ms)')
    fig.legend(*aa[0].get_legend_handles_labels(),loc='lower center',bbox_to_anchor=(.53,.02),ncol=6,frameon=False,fontsize=9);save(fig,out,'Figure_S1',rr)
def figureS2(res,out):
    rr=read(res/'ranking/ranking-results.v1.json')['ranking'];fig,ax=plt.subplots(figsize=(7.8,3.4));fig.subplots_adjust(left=.11,right=.97,top=.97,bottom=.18)
    for y,r in enumerate(rr):
        j=ALGS.index(r['algorithm']);v=r['primaryScore'];lo=r['conservativeSimultaneousScoreLower'];hi=r['conservativeSimultaneousScoreUpper']
        ax.errorbar(v,y,xerr=[[v-lo],[hi-v]],fmt=MARKERS[j],color=COLORS[j],ms=7,capsize=3,lw=1.5);ax.text(98,y,f'{v:.2f}',va='center',ha='right')
    ax.set_yticks(range(6),[r['algorithm'] for r in rr]);ax.set_ylim(5.5,-.5);ax.set_xlim(0,100);ax.grid(axis='x',alpha=.2);ax.set_xlabel('Composite score (higher is preferred)');save(fig,out,'Figure_S2',rr)
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--results',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();out=a.output.resolve()
    if out.exists():p.error('Output must be fresh')
    out.mkdir(parents=True);(out/'source-data').mkdir()
    for f in [figure1,figure2,figure3,figureS1,figureS2]:f(a.results.resolve(),out)
    shutil.copyfile(ROOT/'figure-support/manuscript-embedded/caption-map.csv',out/'captions.csv')
    manifest=[{'file':p.relative_to(out).as_posix(),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(out.rglob('*')) if p.is_file()]
    (out/'FIGURE_MANIFEST.json').write_text(json.dumps({'source':'Recomputed historical results','figures':5,'formats':['PDF','SVG','PNG'],'files':manifest},indent=2),encoding='utf-8')
if __name__=='__main__':main()
