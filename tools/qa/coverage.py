#!/usr/bin/python3 -I
"""Second-pass OCR coverage check: does every printed line of the source pages appear in the exam JSON?

  coverage.py BOOK PAGES {listening|reading} [--strips N]     (PAGES may be 'auto' for reading)

Re-OCRs each page at high zoom in overlapping horizontal strips (an OCR pass independent of the one the extractor
used) and reports lines of >= 4 words whose wording is not found in the module text of BOOK-T*.json
(listening: transcripts; reading: passage titles/paragraphs). Each reported line needs a look at the page image.
"""
import glob, json, os, re, subprocess, sys

IELTS = os.path.expanduser("~/ielts-tools/bin/ielts")
args = [a for a in sys.argv[1:] if not a.startswith("--")]
book, pages_arg, module = args[0], args[1], args[2]
if pages_arg == "auto" and module == "listening":
    # audioscript pages: after the last reading page, pages with several "NAME:" speaker rows or monologue Part headings
    last_reading = 0
    for f in glob.glob(os.path.expanduser(f"~/ielts-data/bank/exams/{book}-T*.json")):
        for p in json.load(open(f)).get("reading", {}).get("passages", []):
            last_reading = max([last_reading] + (p.get("pages") or []))
    ocr = os.path.expanduser(f"~/ielts-data/ocr/{book}")
    total_pages = len([f for f in os.listdir(ocr) if f.endswith(".json")])
    txt = subprocess.run([IELTS, "pagetext", book, f"{last_reading + 1}-{total_pages}"], capture_output=True, text=True).stdout
    found, cur, labels = [], None, 0
    for line in txt.splitlines() + ["===== x page 0"]:
        m = re.match(r"===== \S+ page (\d+)", line)
        if m:
            if cur and labels >= 3:
                found.append(cur)
            cur, labels = int(m.group(1)), 0
        elif re.match(r"\s*[A-Z][A-Z' ]{1,20}:\s+\S", line):
            labels += 1
    if not found:
        sys.exit("could not locate audioscript pages; pass them explicitly")
    # monologue pages (Part 4) have no labels: fill holes between the first and last labelled page
    pages_arg = f"{found[0]}-{found[-1] + 1}"
    print(f"audioscript pages: {pages_arg}", file=sys.stderr)
if pages_arg == "auto":
    # reading: the pages recorded on each passage
    nums = set()
    for f in glob.glob(os.path.expanduser(f"~/ielts-data/bank/exams/{book}-T*.json")):
        for p in json.load(open(f)).get("reading", {}).get("passages", []):
            nums.update(p.get("pages") or [])
    pages_arg = ",".join(map(str, sorted(nums)))
strips = 4
if "--strips" in sys.argv:
    strips = int(sys.argv[sys.argv.index("--strips") + 1])


def norm(t):
    t = t.replace("’", "'").replace("‘", "'").lower()
    t = re.sub(r"\[q[\d/]+\]", " ", t)
    return re.sub(r"[^a-z0-9]+", " ", t).strip()


corpus = []
for f in sorted(glob.glob(os.path.expanduser(f"~/ielts-data/bank/exams/{book}-T*.json"))):
    e = json.load(open(f))
    if module == "listening":
        for p in e.get("listening", {}).get("parts", []):
            corpus.append(p.get("transcript") or "")
    else:
        # every string of the reading module: passages, instructions, questions, options, notes, tables
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
        corpus += list(strings(e.get("reading", {})))
words = norm(" ".join(corpus)).split()
trigrams = {" ".join(words[i:i + 3]) for i in range(len(words) - 2)}


def pages(spec):
    out = []
    for part in spec.split(","):
        a, _, b = part.partition("-")
        out += list(range(int(a), int(b or a) + 1))
    return out


missing = 0
step = 1.0 / strips
for pg in pages(pages_arg):
    seen = set()
    for k in range(strips):
        y = max(0.0, k * step - 0.04)
        h = min(1.0 - y, step + 0.08)
        r = subprocess.run([IELTS, "ocrzoom", book, str(pg), "0", f"{y:.3f}", "1", f"{h:.3f}"], capture_output=True, text=True)
        for line in r.stdout.splitlines():
            m = re.match(r"\s*([\d.]+)\s+([\d.]+)\s+(.*)", line)
            if not m:
                continue
            rel = float(m.group(1))
            text = m.group(3).strip()
            # rows cut by a strip edge come out garbled; the overlapping neighbour strip has them whole
            if (rel < 0.06 and k > 0) or (rel > 0.94 and k < strips - 1):
                continue
            if y + rel * h < 0.05 or y + rel * h > 0.93:      # running header / footer watermark
                continue
            w = norm(re.sub(r"^[A-Z][A-Z' ]+:\s*", "", text)).split()
            w = [x for x in w if not re.fullmatch(r"q\d+", x)]
            if len(w) < 4:
                continue
            key = " ".join(w)
            if key in seen:
                continue
            seen.add(key)
            grams = [" ".join(w[i:i + 3]) for i in range(len(w) - 2)]
            hit = sum(g in trigrams for g in grams) / len(grams)
            if hit < 0.5:
                missing += 1
                print(f"p{pg} y~{y + rel * h:.2f}  ({hit:.0%})  {text[:120]}")
print(f"{missing} lines not found in {module} text", file=sys.stderr)
