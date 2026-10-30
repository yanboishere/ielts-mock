# Brief: convert one Cambridge IELTS book into exam JSON

You are building the question bank of a personal IELTS mock-test app for one user's own study. The source is a
scanned Cambridge IELTS (Academic) book that has already been rendered and OCR'd page by page. Your job: produce one
faithful, validated JSON file per test (Listening + Reading + Writing; skip Speaking and General Training) following
`~/ielts-data/SCHEMA.md`. Read SCHEMA.md completely before starting.

## Tools (all local, no network needed)
`~/ielts-tools/bin/ielts` (run `~/ielts-tools/bin/ielts help`):
* `ielts events BOOK` – first lines of every page (use it to find exact page ranges).
* `ielts pagetext BOOK 12-17` – OCR text with rough layout. `--coords` adds each row's normalized y position
  (useful to choose crop rectangles).
* `ielts pageview BOOK 17` – writes a JPG of the whole page and prints its path; then look at it with the Read tool.
  `ielts pageview BOOK 17 x y w h` – zoomed view of a region (normalized 0..1, origin top-left) – use this for small
  print, tables, answer keys.
* `ielts ocrzoom BOOK 121 x y w h` – re-OCR a region at high zoom (helps when OCR dropped lines).
* `ielts figcrop BOOK 35 x y w h NAME` – save a figure crop into the bank; prints the JSON path to use.
* `ielts findtext BOOK REGEX [pages]` – search the OCR text.
* `ielts assemble BOOK TEST` – merge your work files and validate. `ielts show C15-T1 [module]` – readable rendering
  with answers inline, for proofreading. `ielts answers C15-T1` – compact answer list.

## Work files
Write the three module objects separately (smaller files, easier to fix):
`~/ielts-data/work/BOOK-TN/listening.json` = `{"parts": [...], "answers": {...}}` (+ `"eitherOrder"` if needed)
`~/ielts-data/work/BOOK-TN/reading.json`   = `{"passages": [...], "answers": {...}}`
`~/ielts-data/work/BOOK-TN/writing.json`   = `{"tasks": [...]}`
Any module object may also carry `"issues": ["..."]` (notes about things you could not reproduce faithfully; they are
collected into the exam file). Then run `ielts assemble BOOK N` and fix every ERROR; read the warnings and fix real
problems. A test is done only when assemble prints `OK`. Finish and assemble each test before starting the next one.

## Fidelity rules (most important)
* Reproduce the book exactly: wording, numbering, spelling, capitalisation, punctuation, option letters, titles.
  Fix OCR mistakes – never invent, paraphrase, shorten or "improve" anything. Use British spelling as printed.
* OCR is good for running text but unreliable for: tables, forms, boxed lists of options, single letters (A/B/C),
  roman numerals, numbers next to dotted lines, two-column layouts, and especially the **answer keys** (it often
  drops whole columns of letters). So:
  - **Always view the answer-key pages as images** (zoom into each column) and transcribe every answer from the image;
    use the OCR only as a cross-check. After assembling, run `ielts answers` and compare against the key images again.
  - View every page that has a table, form, notes box, flow chart, map, plan, diagram, or a list of options, and every
    place where the OCR text looks incomplete or garbled. Check that each question number 1–40 appears exactly once.
* Listening transcripts come from the "Audioscripts"/"Tapescripts" section at the back. Include the complete script
  for every part (they are long – that is expected). Remove running headers, page numbers and footers; join wrapped
  lines; one speaker turn per line (`NAME: text`). Keep `[Q7]`-style markers where the book prints them (C13+ books
  print Q-numbers in the margin; older books underline answers – those have no markers, which is fine).
* Reading passages: one paragraph object per printed paragraph, labels (A, B, …) in `label`, footnotes/glossaries as
  `kind: "note"`, in-passage sub-headings as `kind: "heading"`, diagrams that are part of the passage as `kind: "img"`.
* Writing: Task 1 figure must be cropped (`ielts figcrop`, then view the crop to check it is complete and contains no
  question text / page furniture / QR code). Copy the book's sample or model answers (and examiner comments, band)
  from the "Sample/Model answers" section into `sample` when they exist for that task.
* Maps, plans, diagrams and graphical flow charts used by questions must be cropped into the group `image`. Check
  every crop visually. Name crops `BOOK-TN-L2-map`, `BOOK-TN-R1-diagram`, `BOOK-TN-W1`, etc.
* If something is genuinely unreadable or missing in the scan, keep your best faithful reading and record it in
  `issues` (e.g. "Q23 key letter partly cut off in scan; read as C"). Do not leave placeholder text.

## Practicalities
* Do not edit the tools, SCHEMA.md, other books' files or anything outside `~/ielts-data/work/BOOK-*` and
  `~/ielts-data/bank/{exams,images}/BOOK*`.
* Write JSON with a real JSON writer mindset: escape quotes properly, no comments, no trailing commas. Use the Write
  tool for each module file (it is fine if a file is long).
* Be economical with image views: use zoomed regions for detail instead of many full pages, but never skip the checks
  listed above.
* When finished, reply with a short report: for each test the assemble status, the number of warnings left, and any
  `issues` you recorded.

## Network constraints (learned the hard way)
* The API gateway kills any single response that takes too long to generate. Never emit more than ~3 KB of content in
  one tool call. Build module files incrementally: write a small skeleton, then append paragraphs (one or two at a time),
  question groups and answers in small pieces, e.g. with a tiny Python helper run via Bash. Save as you go.
* View page images only as zoomed regions (height ≤ 0.35), never whole pages.
* If requests start failing with HTTP 400 "upstream rejected the request" right after you viewed a page image, that image
  (often a photograph printed on the page) is being rejected upstream. Do not view that page again; finish it from text
  only (`ielts pagetext`, `ielts ocrzoom` on small regions) and mention the page in your report.
* If requests keep failing with HTTP 400 while you are writing a particular passage (even without images), the passage
  text itself is being rejected when it appears in your response. Stop emitting that text: write a small Python script
  that rebuilds the remaining paragraphs from the OCR rows (`ielts pagetext --coords` / `ielts ocrzoom` per column) and
  appends them straight into the JSON; print only paragraph counts and the first/last few words to verify.
* Third-party stamps: some older scans (C4–C8) have blue/red watermark stamps (luckbar.com, QQ numbers, TopSage) printed
  over figures. After cropping a black-and-white figure that carries such a stamp, back it up to
  ~/ielts-data/bank/images-orig/BOOK/ and run `~/ielts-tools/qa/dewatermark IMAGE`, then view the result. Never run it on
  figures that are genuinely in colour (e.g. C9's retyped charts).
