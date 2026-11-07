"""Compile a fresh copy of the minimal project and run functional checks."""
from pathlib import Path
import argparse,json,hashlib,shutil,subprocess,sys,os
def main():
    p=argparse.ArgumentParser();p.add_argument('--unity',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--timeout',type=int,default=600);a=p.parse_args()
    root=Path(__file__).resolve().parents[1];source=root/'unity-minimal';out=a.output.resolve()
    if out.exists():p.error('Choose a new output directory')
    if not a.unity.is_file():p.error('Unity executable not found')
    for r in json.loads((source/'source-identities.json').read_text()):
        assert hashlib.sha256((source/r['path']).read_bytes()).hexdigest()==r['sha256'],r['path']
    out.mkdir(parents=True);project=out/'project';shutil.copytree(source,project)
    command=[str(a.unity.resolve()),'-batchmode','-nographics','-projectPath',str(project),'-executeMethod','PortableNavigationCheck.Run','-portableResult',str(out/'functional-check.json'),'-logFile',str(out/'unity.log')]
    with (out/'process-output.txt').open('w',encoding='utf-8') as log:
        result=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=a.timeout,creationflags=subprocess.CREATE_NO_WINDOW if os.name=='nt' else 0)
    receipt=json.loads((out/'functional-check.json').read_text()) if (out/'functional-check.json').is_file() else {'status':'FAIL','reason':'No functional receipt; inspect unity.log'}
    report={'status':'PASS' if result.returncode==0 and receipt.get('status')=='PASS' and receipt.get('checkCount')==120 else 'FAIL','process_exit_code':result.returncode,'unity_version':receipt.get('unityVersion'),'checks':receipt.get('checkCount'),'source_identity_count':7,'output':str(out)}
    (out/'validation.json').write_text(json.dumps(report,indent=2));print(json.dumps(report,indent=2));return 0 if report['status']=='PASS' else 1
if __name__=='__main__':sys.exit(main())
