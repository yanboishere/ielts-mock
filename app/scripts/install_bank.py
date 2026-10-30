#!/usr/bin/python3 -I
"""Install the generated Cambridge IELTS bank into the app's data folder.

  scripts/install_bank.py [--src DIR] [--dest DIR] [--no-pages] [--only C15-T1,C15-T2]

Sources (defaults):
  ~/ielts-data/bank/exams/*.json + images/        exam JSON produced by the extraction pipeline
  ~/ielts-data/build/audiomap.json               C{book}-T{test}-P{part} -> path under the audio repo
  ~/ielts-refs/zeeklog/repo/雅思真题音频          audio files (cloned with `cp -c`, no extra disk space on APFS)
  ~/ielts-data/ocr/C{book}/pNNNN.jpg              page renders (downscaled copies go to pages/ for "原书页面")
Destination default: ~/Library/Application Support/IELTSMock/Bank
"""
import json, os, shutil, subprocess, sys

HOME = os.path.expanduser("~")
SRC = os.path.join(HOME, "ielts-data", "bank")
AUDIOMAP = os.path.join(HOME, "ielts-data", "build", "audiomap.json")
AUDIOROOT = os.path.join(HOME, "ielts-refs", "zeeklog", "repo", "雅思真题音频")
OCR = os.path.join(HOME, "ielts-data", "ocr")
SCHEMA = os.path.join(HOME, "ielts-data", "SCHEMA.md")


def clone(src, dst):
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    if os.path.exists(dst):
        if os.path.getsize(dst) == os.path.getsize(src):
            return
        os.remove(dst)
    r = subprocess.run(["/bin/cp", "-c", src, dst], capture_output=True)
    if r.returncode != 0:
        shutil.copy2(src, dst)


def main():
    args = sys.argv[1:]
    dest = os.path.join(HOME, "Library", "Application Support", "IELTSMock", "Bank")
    pages = True
    only = None
    i = 0
    while i < len(args):
        if args[i] == "--src":
            global SRC
            SRC = os.path.expanduser(args[i + 1]); i += 2; continue
        if args[i] == "--dest":
            dest = os.path.expanduser(args[i + 1]); i += 2; continue
        if args[i] == "--no-pages":
            pages = False; i += 1; continue
        if args[i] == "--only":
            only = set(args[i + 1].split(",")); i += 2; continue
        sys.exit(__doc__)
    audiomap = json.load(open(AUDIOMAP)) if os.path.exists(AUDIOMAP) else {}
    os.makedirs(os.path.join(dest, "exams"), exist_ok=True)
    exams = sorted(f for f in os.listdir(os.path.join(SRC, "exams")) if f.endswith(".json"))
    installed, missing_audio = 0, []
    for f in exams:
        eid = f[:-5]
        if only and eid not in only:
            continue
        exam = json.load(open(os.path.join(SRC, "exams", f)))
        book = f"C{exam['source']['book']}"
        test = exam["source"]["test"]
        # audio
        for p in exam.get("listening", {}).get("parts", []):
            key = f"{book}-T{test}-P{p['part']}"
            rel = audiomap.get(key)
            if rel and os.path.exists(os.path.join(AUDIOROOT, rel)):
                ext = os.path.splitext(rel)[1].lower()
                target = f"audio/{book}/T{test}/P{p['part']}{ext}"
                clone(os.path.join(AUDIOROOT, rel), os.path.join(dest, target))
                p["audio"] = target
            else:
                p["audio"] = None
                missing_audio.append(key)
        # page images
        if pages:
            nums = set()
            for p in exam.get("listening", {}).get("parts", []):
                nums.update(p.get("pages") or [])
            for p in exam.get("reading", {}).get("passages", []):
                nums.update(p.get("pages") or [])
            for t in exam.get("writing", {}).get("tasks", []):
                nums.update(t.get("pages") or [])
            for n in sorted(nums):
                src = os.path.join(OCR, book, f"p{n:04d}.jpg")
                dst = os.path.join(dest, "pages", book, f"p{n:04d}.jpg")
                if os.path.exists(src) and not os.path.exists(dst):
                    os.makedirs(os.path.dirname(dst), exist_ok=True)
                    subprocess.run(["/usr/bin/sips", "-Z", "1300", "-s", "formatOptions", "70", src, "--out", dst], capture_output=True)
        json.dump(exam, open(os.path.join(dest, "exams", f), "w"), ensure_ascii=False, indent=1)
        installed += 1
    # images
    src_img = os.path.join(SRC, "images")
    if os.path.isdir(src_img):
        for root, _, files in os.walk(src_img):
            for fn in files:
                s = os.path.join(root, fn)
                d = os.path.join(dest, "images", os.path.relpath(s, src_img))
                if not os.path.exists(d) or os.path.getmtime(s) > os.path.getmtime(d):
                    os.makedirs(os.path.dirname(d), exist_ok=True)
                    shutil.copy2(s, d)
    if os.path.exists(SCHEMA):
        shutil.copy2(SCHEMA, os.path.join(dest, "SCHEMA.md"))
    print(f"installed {installed} exams into {dest}")
    if missing_audio:
        print("missing audio:", ", ".join(missing_audio))


if __name__ == "__main__":
    main()
