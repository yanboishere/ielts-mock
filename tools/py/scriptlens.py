import json, sys, os, re
sys.path.insert(0, os.path.dirname(__file__))
from ocrtext import rows_of
book, a, b = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
text = []
for p in range(a, b + 1):
    d = json.load(open(os.path.join(book, f"p{p:04d}.json")))
    for r in rows_of(d):
        text.append(" ".join(it["t"] for it in sorted(r["items"], key=lambda l: l["x"])))
cur = None; counts = {}; test = 0
for line in text:
    m = re.match(r"^\s*(TEST|Test)\s*([1-8])\b", line)
    if m and len(line) < 20: test = int(m.group(2))
    m2 = re.match(r"^\s*(SECTION|PART)\s*([1-4])\b", line)
    if m2 and len(line) < 20:
        sec = int(m2.group(2))
        if sec == 1 and cur and cur[1] != 1 and test == cur[0]: test += 1
        cur = (test, sec)
        continue
    if cur: counts[cur] = counts.get(cur, 0) + len(line.split())
for k in sorted(counts): print(k, counts[k])
