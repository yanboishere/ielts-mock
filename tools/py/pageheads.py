import json, sys, os, glob
sys.path.insert(0, os.path.dirname(__file__))
from ocrtext import rows_of
book = sys.argv[1]
n = int(sys.argv[2]) if len(sys.argv) > 2 else 3
for f in sorted(glob.glob(os.path.join(book, "p*.json"))):
    d = json.load(open(f))
    rows = rows_of(d)
    texts = [" ".join(it["t"] for it in sorted(r["items"], key=lambda l: l["x"])) for r in rows]
    texts = [t for t in texts if len(t.strip()) > 1]
    print(os.path.basename(f)[1:5].lstrip("0") + ": " + " | ".join(texts[:n])[:170])
