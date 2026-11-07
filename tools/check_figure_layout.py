"""Check comparable axes in the study figures using rendered positions in points."""
from pathlib import Path
import itertools,json

def require_matplotlib_panel_alignment(fig, json_out, strict=True, tolerance_pt=1.5):
    fig.canvas.draw()
    width,height=fig.get_size_inches()*72
    panels=[]
    for i,axis in enumerate(fig.axes):
        spec=axis.get_subplotspec()
        if spec is None: continue
        box=axis.get_position()
        panels.append({"axis":i,"row":[spec.rowspan.start,spec.rowspan.stop],
                       "column":[spec.colspan.start,spec.colspan.stop],
                       "rectangle_pt":[box.x0*width,box.y0*height,box.x1*width,box.y1*height]})
    checks=[]
    for a,b in itertools.combinations(panels,2):
        aa,bb=a["rectangle_pt"],b["rectangle_pt"]
        if a["row"]==b["row"]:
            checks.append({"axes":[a["axis"],b["axis"]],"check":"row_edges","error_pt":max(abs(aa[1]-bb[1]),abs(aa[3]-bb[3]))})
            if a["column"][1]-a["column"][0]==b["column"][1]-b["column"][0]:
                checks.append({"axes":[a["axis"],b["axis"]],"check":"equal_span_width","error_pt":abs((aa[2]-aa[0])-(bb[2]-bb[0]))})
        if a["column"]==b["column"]:
            checks.append({"axes":[a["axis"],b["axis"]],"check":"column_edges","error_pt":max(abs(aa[0]-bb[0]),abs(aa[2]-bb[2]))})
    failures=[c for c in checks if c["error_pt"]>tolerance_pt]
    report={"status":"FAIL" if failures else "PASS","scope":"Comparable axes edges and equal-span widths; not a font or collision audit", "tolerance_pt":tolerance_pt,"panels":panels,"checks":checks,"failures":failures}
    Path(json_out).write_text(json.dumps(report,indent=2),encoding="utf-8")
    if strict and failures: raise ValueError("Figure panel alignment failed: "+str(failures))
    return report
