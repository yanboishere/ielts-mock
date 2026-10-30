import os, re, json, sys
root = os.path.expanduser("~/ielts-refs/zeeklog/repo/雅思真题音频")
out = {}
for d in sorted(os.listdir(root)):
    m = re.match(r"(\d+)-剑桥雅思(\d+)", d)
    if not m: continue
    book = int(m.group(2))
    for dirpath, _, files in os.walk(os.path.join(root, d)):
        for f in files:
            if not re.search(r"\.(mp3|m4a)$", f, re.I): continue
            rel = os.path.relpath(os.path.join(dirpath, f), root)
            name = f
            t = p = None
            pats = [
                r"Test\s*(\d)\s*[._-]?\s*Sect?i?on\s*(\d)",       # Test1.Section1 / Test4.Secton3
                r"Test\s*(\d)-s(\d)",                             # Test1-s1
                r"Test\s*(\d)_Section(\d)",
                r"^section(\d)-(\d)",                             # C5: section{test}-{section}
                r"_section(\d)-(\d)",
                r"Test\s*(\d)-(\d)",                              # C14: Test 1-1
                r"Test\s*(\d)\s*Part\s*(\d)",                     # C16
                r"test(\d)_audio(\d)",                            # C15
                r"_t(\d)_audio(\d)",                              # C17
                r"section(\d)\s*-?\s*part(\d)",                   # C18
            ]
            for pat in pats:
                mm = re.search(pat, name, re.I)
                if mm: t, p = int(mm.group(1)), int(mm.group(2)); break
            if t is None:
                print("UNMAPPED", rel); continue
            if p == 5: p = 4   # C13 Test4.Section5 is actually Section 4
            key = f"C{book}-T{t}-P{p}"
            if key in out: print("DUP", key, rel, out[key])
            out[key] = rel
json.dump(out, open(os.path.expanduser("~/ielts-data/build/audiomap.json"), "w"), ensure_ascii=False, indent=1)
# report coverage
tests = {12: [5, 6, 7, 8]}
missing = []
for b in range(4, 19):
    for t in tests.get(b, [1, 2, 3, 4]):
        for p in range(1, 5):
            if f"C{b}-T{t}-P{p}" not in out: missing.append(f"C{b}-T{t}-P{p}")
print("mapped", len(out), "missing", missing)
