#!/usr/bin/python3 -I
"""Second stage of coverage.py: fuzzy-match each flagged line against the book's JSON text.

  confirm_flags.py BOOK            (reads ~/ielts-data/qa/BOOK.txt)
Prints only flags whose best character-level similarity is below 0.8 (likely genuinely missing or not text).
"""
import difflib, glob, json, os, re, sys

book = sys.argv[1]
def norm(t):
    t = t.lower().replace("’", "'")
    t = re.sub(r"\[q[\d/ &q]+\]", " ", t)
    return re.sub(r"[^a-z0-9]+", " ", t).strip()

def strings(o):
    if isinstance(o, str):
        yield re.sub(r"\{\{\d+\}\}", " ", o)
    elif isinstance(o, dict):
        for k, v in o.items():
            if k not in ("answers", "issues"):
                yield from strings(v)
    elif isinstance(o, list):
        for v in o:
            yield from strings(v)

text = " ".join(norm(s) for f in glob.glob(os.path.expanduser(f"~/ielts-data/bank/exams/{book}-T*.json"))
                for s in strings({k: v for k, v in json.load(open(f)).items() if k in ("listening", "reading")}))
words = text.split()
left = 0
for line in open(os.path.expanduser(f"~/ielts-data/qa/{book}.txt")):
    m = re.match(r"(p\d+ y~[\d.]+)\s+\(\d+%\)\s+(.*)", line.rstrip())
    if not m:
        continue
    q = norm(re.sub(r"^[A-Z][A-Z' ]+:\s*", "", m.group(2)))
    qw = q.split()
    if len(qw) < 3:
        continue
    n = len(qw)
    best = 0.0
    # candidate windows: positions sharing any rare-ish word with the query
    anchors = {w for w in qw if len(w) > 4} or set(qw)
    for i, w in enumerate(words):
        if w in anchors:
            for s in range(max(0, i - n), i + 1):
                r = difflib.SequenceMatcher(None, q, " ".join(words[s:s + n])).ratio()
                if r > best:
                    best = r
            if best > 0.9:
                break
    if best < 0.8:
        left += 1
        print(f"{m.group(1)}  sim={best:.2f}  {m.group(2)[:110]}")
print(f"{left} flags not explained by fuzzy match", file=sys.stderr)
