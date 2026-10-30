#!/usr/bin/python3 -I
"""Flag places in audioscript pages where OCR rows are spaced unusually far apart (a likely dropped line).

  ocr_gaps.py BOOK FIRST-LAST [factor]

If exam files exist in ~/ielts-data/bank/exams/BOOK-T*.json, each gap is cross-checked against the transcripts:
"filled" = the transcript has extra text between the rows around the gap (the extractor restored it);
"UNRESOLVED" = the transcript jumps straight across the gap, so a dropped line may be missing; view the page.

Prints page, y range and the rows around each suspicious gap. Gaps right before PART/SECTION headings,
page tops/bottoms are ignored.
"""
import re, subprocess, sys, statistics

book, rng = sys.argv[1], sys.argv[2]
args = [a for a in sys.argv[1:] if not a.startswith("--")]
factor = float(args[2]) if len(args) > 2 else 1.75
out = subprocess.run([__import__("os").path.expanduser("~/ielts-tools/bin/ielts"), "pagetext", book, rng, "--coords"],
                     capture_output=True, text=True).stdout
pages, cur = {}, None
for line in out.splitlines():
    m = re.match(r"===== \S+ page (\d+)", line)
    if m:
        cur = int(m.group(1)); pages[cur] = []; continue
    m = re.match(r"\[y([\d.]+)\]\s?(.*)", line)
    if m and cur is not None:
        pages[cur].append((float(m.group(1)), m.group(2).strip()))
import glob, json, os
def norm(t):
    return re.sub(r"[^a-z0-9]+", " ", t.lower()).strip()
transcript = ""
for f in sorted(glob.glob(os.path.expanduser(f"~/ielts-data/bank/exams/{book}-T*.json"))):
    for part in json.load(open(f)).get("listening", {}).get("parts", []):
        transcript += " " + norm(re.sub(r"\[Q[\d/]+\]", " ", part.get("transcript") or ""))
transcript = " " + transcript + " "

def anchor(text, last):
    """Position in the transcript of a row's text: the end of its last words, or the start of its first words."""
    words = norm(re.sub(r"^[A-Z][A-Z' ]+:\s*", "", text)).split()
    words = [w for w in words if not re.fullmatch(r"q\d+", w)]
    if len(words) < 3:
        return None
    probe = " ".join(words[-5:] if last else words[:5])
    i = transcript.find(" " + probe + " ")
    if i < 0:
        return None
    return i + len(probe) + 1 if last else i

total = unresolved = 0
for p, rows in pages.items():
    rows = [r for r in rows if 0.06 < r[0] < 0.94 and r[1]]
    if len(rows) < 8:
        continue
    gaps = [b[0] - a[0] for a, b in zip(rows, rows[1:])]
    # typical spacing between turns (a new speaker line is slightly further than a wrapped line)
    med = statistics.median(gaps)
    for i, g in enumerate(gaps):
        nxt = rows[i + 1][1]
        if g > med * factor * 1.25 and not re.match(r"(PART|SECTION|TEST|Test|Audioscripts|AUDIOSCRIPTS|Tapescripts)\b", nxt) \
                and not re.fullmatch(r"[\d\s]+", nxt):
            total += 1
            a, b = anchor(rows[i][1], True), anchor(nxt, False)
            if a is None or b is None:
                verdict = "UNCHECKED (row text not found in transcript)"
            elif b - a > 25:
                verdict = f"filled (+{b - a} chars in transcript)"
            else:
                verdict = "UNRESOLVED"
            if not verdict.startswith("filled"):
                unresolved += 1
            if "--all" not in sys.argv and verdict.startswith("filled"):
                continue
            print(f"p{p} y{rows[i][0]:.3f}->{rows[i+1][0]:.3f} (gap {g:.3f}, median {med:.3f})  {verdict}")
            print(f"    | {rows[i][1][:110]}")
            print(f"    | {nxt[:110]}")
print(f"{total} suspicious gaps, {unresolved} not explained by the transcript", file=sys.stderr)
