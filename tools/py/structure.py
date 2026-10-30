import json, sys, os, glob, re
sys.path.insert(0, os.path.dirname(__file__))
from ocrtext import rows_of

def page_rows(f):
    d = json.load(open(f))
    return [" ".join(it["t"] for it in sorted(r["items"], key=lambda l: l["x"])) for r in rows_of(d)]

book = sys.argv[1]
marks = []
for f in sorted(glob.glob(os.path.join(book, "p*.json"))):
    p = int(os.path.basename(f)[1:5])
    rows = page_rows(f)
    top = " | ".join(rows[:6])
    full = "\n".join(rows)
    tags = []
    m = re.search(r"\bTest\s*([1-8])\b", " ".join(rows[:3]), re.I)
    if m: tags.append("T" + m.group(1))
    for kw, tag in [("LISTENING", "L"), ("READING", "R"), ("WRITING", "W"), ("SPEAKING", "S")]:
        if re.search(r"^\s*" + kw + r"\b", top, re.M) or re.search(r"\|\s*" + kw + r"\b", top) or re.search(r"\b" + kw + r"\s*$", " ".join(rows[:2])):
            tags.append(tag)
    if re.search(r"(Tapescript|Audioscript|TAPESCRIPT|AUDIOSCRIPT|Transcript)", top): tags.append("SCRIPT")
    if re.search(r"answer\s*key", top, re.I): tags.append("KEY")
    if re.search(r"General Training", top, re.I): tags.append("GT")
    if re.search(r"(Model|Sample)\s+(and sample )?(Writing )?answers?", top, re.I): tags.append("SAMPLE")
    if re.search(r"SECTION\s*1|PART\s*1\s+Questions\s*1", full): tags.append("L-P1")
    if re.search(r"READING PASSAGE\s*1", full): tags.append("R-P1")
    if re.search(r"WRITING TASK\s*1", full): tags.append("W1")
    print(f"{p:3d} {' '.join(tags):28s} {top[:120]}")
