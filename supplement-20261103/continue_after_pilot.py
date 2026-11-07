from pathlib import Path
import time,json,subprocess,sys,datetime
p=Path(__file__).resolve().parent
started=time.monotonic()
while not (p/'pilot-complete.json').exists():
 s=json.loads((p/'status.json').read_text(encoding='utf-8'))
 if s.get('status')=='STOPPED_ERROR':raise RuntimeError('Pilot stopped: '+s.get('error',''))
 if time.monotonic()-started>3600:raise TimeoutError('Pilot did not complete within one hour; formal not launched')
 time.sleep(2)
r=json.loads((p/'pilot-complete.json').read_text(encoding='utf-8'))
assert r['passed'] and r['completed']==25
if (p/'formal-launch.json').exists():raise RuntimeError('Formal launch already recorded')
(p/'formal-launch.json').write_text(json.dumps({'startedUtc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'pilotCompleted':True,'command':[sys.executable,str(p/'supervisor.py'),'formal']},indent=2),encoding='utf-8')
with (p/'formal-supervisor.stdout.log').open('xb') as out, (p/'formal-supervisor.stderr.log').open('xb') as err:
 proc=subprocess.Popen([sys.executable,str(p/'supervisor.py'),'formal'],stdout=out,stderr=err,creationflags=subprocess.CREATE_NO_WINDOW)
 (p/'formal-supervisor-pid.json').write_text(json.dumps({'pid':proc.pid,'startedUtc':datetime.datetime.now(datetime.timezone.utc).isoformat()}),encoding='utf-8')
 code=proc.wait()
 if code:raise RuntimeError('Formal supervisor stopped; inspect status.json')
