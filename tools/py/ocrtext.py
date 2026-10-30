import json, sys, os

def rows_of(d):
    lines = sorted(d["lines"], key=lambda l: (l["y"], l["x"]))
    rows = []
    for l in lines:
        cy = l["y"] + l["h"] / 2
        best = None
        for r in rows[-4:]:
            if abs(r["cy"] - cy) < min(r["h"], l["h"]) * 0.45:
                best = r; break
        if best is not None:
            best["items"].append(l)
        else:
            rows.append({"cy": cy, "h": l["h"], "items": [l]})
    rows.sort(key=lambda r: r["cy"])
    return rows

def page_text(path, cols=110, indent=True):
    d = json.load(open(path))
    out = []
    for r in rows_of(d):
        s = ""
        for it in sorted(r["items"], key=lambda l: l["x"]):
            col = int(it["x"] * cols) if indent else 0
            if len(s) < col: s += " " * (col - len(s))
            elif s: s += "  "
            s += it["t"]
        out.append(s.rstrip())
    # remove common left margin
    nonempty = [l for l in out if l.strip()]
    if nonempty:
        m = min(len(l) - len(l.lstrip()) for l in nonempty)
        out = [l[m:] for l in out]
    return "\n".join(out)

if __name__ == "__main__":
    for p in sys.argv[1:]:
        print(f"===== {os.path.basename(p)}")
        print(page_text(p))
