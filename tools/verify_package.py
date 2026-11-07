from pathlib import Path
import argparse,csv,hashlib,json,zipfile,sys
def sha(p):
 with p.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--archives',type=Path);ap.add_argument('--deep',action='store_true');args=ap.parse_args()
 root=Path(__file__).resolve().parents[1];checked=0;errors=[];archives=0;entries=0
 with (root/'MANIFEST_SHA256.csv').open(encoding='utf-8-sig',newline='') as f:
  for row in csv.DictReader(f):
   p=root/row['path']
   if not p.is_file() or p.stat().st_size!=int(row['bytes']) or sha(p)!=row['sha256']:errors.append(row['path'])
   checked+=1
 if args.archives:
  indexes={}
  for p in args.archives.glob('*.files.csv'):
   with p.open(encoding='utf-8',newline='') as f:
    for row in csv.DictReader(f):indexes.setdefault(row['archive'],{})[row['path']]=row
  for row in json.loads((args.archives/'archives.json').read_text()):
   p=args.archives/row['archive'];archives+=1
   if p.stat().st_size!=row['bytes'] or sha(p)!=row['sha256']:errors.append(p.name)
   expected=indexes[p.name]
   with zipfile.ZipFile(p) as z:
    if set(z.namelist())!=set(expected):errors.append(p.name+': members')
    for item in z.infolist():
     entries+=1;r=expected[item.filename]
     if item.file_size!=int(r['bytes']):errors.append(item.filename+': size')
     if args.deep:
      with z.open(item) as f:
       if hashlib.file_digest(f,'sha256').hexdigest()!=r['sha256']:errors.append(item.filename+': hash')
 result={'status':'PASS' if not errors else 'FAIL','repository_files':checked,'archives':archives,'archive_entries':entries,'deep_payload_hashes_checked':args.deep,'errors':errors}
 print(json.dumps(result,indent=2));return int(bool(errors))
if __name__=='__main__':sys.exit(main())
