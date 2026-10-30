import json,sys
f='/Users/owo/ielts-data/work/C10-T1/reading.json'
d=json.load(open(f))
p=d['passages'][2]
obj=json.loads(sys.stdin.read())
if sys.argv[1:]==['ans']: d['answers'].update(obj)
else: p['groups'].append(obj)
json.dump(d,open(f,'w'),ensure_ascii=False,indent=1)
print(len(p['groups']),len(d['answers']))
