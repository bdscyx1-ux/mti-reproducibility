"""Run an analysis script while rejecting access to original acquisition roots."""
import sys,os,runpy,json
from pathlib import Path
def guard(event,args):
    if event not in ('open','os.listdir','os.scandir'):return
    if not args or not isinstance(args[0],(str,bytes,os.PathLike)):return
    value=os.fsdecode(args[0]).replace('\\','/').lower()
    if any('/'+x+'/' in value+'/' for x in ('ddm_final_project','ddm_revision_20261103')):
        raise PermissionError('Original acquisition root access prohibited: '+value)
    for root in json.loads(os.environ.get('MTI_FORBIDDEN_ROOTS','[]')):
        root=str(root).replace('\\','/').rstrip('/').lower()
        if value==root or value.startswith(root+'/'):
            raise PermissionError('Explicitly forbidden source root: '+value)
if __name__=='__main__':
    script=Path(sys.argv[1]).resolve();sys.argv=sys.argv[1:];sys.path.insert(0,str(script.parent))
    sys.addaudithook(guard)
    runpy.run_path(str(script),run_name='__main__')
