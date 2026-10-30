import json, sys, os, glob, re
sys.path.insert(0, os.path.dirname(__file__))
from ocrtext import rows_of

def rows(f):
    d = json.load(open(f))
    return [" ".join(it["t"] for it in sorted(r["items"], key=lambda l: l["x"])) for r in rows_of(d)]

book = sys.argv[1]
ev = []
last = None
for f in sorted(glob.glob(os.path.join(book, "p*.json"))):
    p = int(os.path.basename(f)[1:5])
    rs = rows(f)
    top = "\n".join(rs[:8])
    full = "\n".join(rs)
    e = []
    if re.search(r"General Training", top): e.append("GT")
    if re.search(r"(Tapescripts?|Audioscripts?|TAPESCRIPTS?|AUDIOSCRIPTS?)", top): e.append("SCRIPTS")
    if re.search(r"answer\s*keys?|Answer\s*Key|ANSWER KEY", top, re.I) and not re.search(r"Introduction", top): e.append("KEYS")
    if re.search(r"(Model and sample answers|Sample (Writing )?answers|Model answers|Sample answer)", top, re.I) and not re.search(r"Introduction", top): e.append("SAMPLES")
    if re.search(r"(SECTION|PART)\s*1\s+Questions?\s*1\s*[-–—]\s*\d", full) or re.search(r"^LISTENING\b", top, re.M): e.append("L")
    if re.search(r"READING PASSAGE\s*1\b", full) or re.search(r"READING\s+PASSAGE\s+I\b", full): e.append("R1")
    if re.search(r"READING PASSAGE\s*2\b", full): e.append("R2")
    if re.search(r"READING PASSAGE\s*3\b", full): e.append("R3")
    if re.search(r"WRITING TASK\s*1\b", full): e.append("W1")
    if re.search(r"WRITING TASK\s*2\b", full): e.append("W2")
    if re.search(r"^\s*SPEAKING\b", top, re.M): e.append("S")
    m = re.findall(r"\b(?:Test|TEST)\s*([1-8A-B])\b", top)
    t = m[0] if m else ""
    if e:
        ev.append(f"{p}:{'+'.join(e)}{('@T'+t) if t else ''}")
print(book, " ".join(ev))
