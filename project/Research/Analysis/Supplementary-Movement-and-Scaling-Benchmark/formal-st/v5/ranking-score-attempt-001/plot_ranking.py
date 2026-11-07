from __future__ import annotations
import csv
import json
import sys
from pathlib import Path

import numpy as np
import matplotlib as mpl
mpl.use('Agg')
import matplotlib.pyplot as plt

sys.path.insert(0,r'C:\Users\bdscy\.agents\skills\nature-figure\scripts')
from audit_panel_alignment import require_matplotlib_panel_alignment

ROOT=Path(__file__).resolve().parent
OUT=ROOT/'figures';OUT.mkdir(exist_ok=True)
r=json.loads((ROOT/'ranking-results.v1.json').read_text('utf-8'))
rows=r['ranking']; algs=[x['algorithm'] for x in rows]
colors={'A*-R':'#757575','BiA*-R':'#A6A6A6','D*L':'#4C78A8','LPA*':'#72A2BA','C-FF':'#D58936','IDFF':'#20776D'}
markers={'A*-R':'o','BiA*-R':'s','D*L':'^','LPA*':'v','C-FF':'D','IDFF':'P'}
mpl.rcParams.update({'font.family':'sans-serif','font.sans-serif':['Arial','DejaVu Sans'],
    'font.size':8,'axes.labelsize':8,'axes.titlesize':8.5,'xtick.labelsize':7.5,'ytick.labelsize':7.5,
    'pdf.fonttype':42,'svg.fonttype':'none','axes.spines.top':False,'axes.spines.right':False,
    'axes.linewidth':.65,'legend.frameon':False,'savefig.facecolor':'white'})
fig,ax=plt.subplots(2,2,figsize=(7.204724,6.5))
fig.subplots_adjust(left=.115,right=.98,top=.93,bottom=.12,hspace=.50,wspace=.45)
titles=['Priority score and uncertainty','Utility by domain','Sensitivity to runtime priority','Sensitivity to domain weights']
for i,a in enumerate(ax.flat):
    a.set_title(titles[i],loc='left',pad=10)
    a.annotate(chr(97+i),xy=(0,1),xycoords='axes fraction',xytext=(-28,17),textcoords='offset points',
               fontsize=10,fontweight='bold',ha='left',va='bottom',annotation_clip=False)
for i,row in enumerate(rows):
    s=row['primaryScore'];l=row['conservativeSimultaneousScoreLower'];u=row['conservativeSimultaneousScoreUpper']
    assert 0<=l<=s<=u<=100
    ax[0,0].errorbar(s,i,xerr=[[s-l],[u-s]],fmt=markers[row['algorithm']],ms=5,color=colors[row['algorithm']],capsize=2,lw=1)
ax[0,0].set(yticks=range(6),yticklabels=algs,ylim=(5.6,-.7),xlim=(0,100),xlabel='Composite score (higher is preferred)')
ax[0,0].grid(axis='x',color='#EAEAEA',lw=.5)
u=np.array([[row[d+'Utility'] for d in ['D1','D2','D3','D4','D5','D6','D7']] for row in rows])
assert u.min()>=0 and u.max()<=100
ax[0,1].imshow(u,cmap='Blues',vmin=0,vmax=100,aspect='auto',interpolation='nearest')
ax[0,1].set(yticks=range(6),yticklabels=algs,xticks=range(7),xticklabels=['D1','D2','D3','D4','D5','D6','D7'],xlabel='Domain utility (0–100)')
for i in range(6):
    for j in range(7):
        ax[0,1].text(j,i,f'{u[i,j]:.0f}',ha='center',va='center',fontsize=7,color='white' if u[i,j]>=65 else '#202020')
with (ROOT/'runtime-weight-sensitivity.v1.csv').open(encoding='utf-8-sig',newline='') as f:
    sweep=list(csv.DictReader(f))
x=np.array([float(s['runtimeGroupWeight']) for s in sweep])
assert np.all(np.diff(x)>0)
for a in algs:
    y=np.array([float(s[a]) for s in sweep])
    ax[1,0].plot(x,y,color=colors[a],marker=markers[a],markevery=40,ms=3,lw=1.1,label=a,linestyle='--' if a=='LPA*' else '-')
ax[1,0].axvline(.7,color='#555555',ls='--',lw=.7)
ax[1,0].set(xlim=(0,1),ylim=(0,100),xlabel='Total D1–D3 weight',ylabel='Composite score')
ax[1,0].grid(axis='y',color='#EAEAEA',lw=.5)
for i,row in enumerate(rows):
    a=row['algorithm'];lo,hi=r['sensitivity']['cornerScoreRanges'][a]
    ax[1,1].plot([lo,hi],[i,i],lw=2,color=colors[a],solid_capstyle='butt')
    ax[1,1].plot(row['primaryScore'],i,marker=markers[a],ms=5,color=colors[a])
ax[1,1].set(yticks=range(6),yticklabels=algs,ylim=(5.6,-.6),xlim=(0,100),xlabel='Score across 128 weight scenarios')
ax[1,1].grid(axis='x',color='#EAEAEA',lw=.5)
handles,labels=ax[1,0].get_legend_handles_labels()
fig.legend(handles,labels,loc='lower center',bbox_to_anchor=(.53,.015),ncol=6,fontsize=7.5,handlelength=1.6,columnspacing=1.)
fig.canvas.draw()
require_matplotlib_panel_alignment(fig,json_out=str(OUT/'figure5_gate14reme_ranking.alignment.json'),
    overlay_svg=str(OUT/'figure5_gate14reme_ranking.alignment.svg'),tolerance_pt=1.5,gutter_tolerance_pt=1.5,strict=True)
name=OUT/'figure5_gate14reme_ranking'
fig.savefig(str(name)+'.pdf')
fig.savefig(str(name)+'.svg')
fig.savefig(str(name)+'.png',dpi=300)
fig.savefig(str(name)+'.tiff',dpi=600)
plt.close(fig)
print('Ranking figure exported in PDF, SVG, PNG and TIFF.')
