# Brief: add the Speaking module to one Cambridge IELTS book

The listening/reading/writing modules of every test are done. Your job: for each test of ONE book, transcribe the
Speaking test page(s) into `~/ielts-data/work/BOOK-TN/speaking.json` following the "Speaking" section at the end of
`~/ielts-data/SCHEMA.md` (read it first), then run `~/ielts-tools/bin/ielts assemble BOOK N` until it prints OK.

* Find the pages: `~/ielts-tools/bin/ielts findtext BOOK "^ *SPEAKING *$"` (the first hits may be the introduction —
  each test has one Speaking page right after its Writing pages; C12's tests are numbered 5–8).
  Read it with `ielts pagetext BOOK PAGE` and check every page as a zoomed image (`ielts pageview BOOK PAGE x y w h`,
  height ≤ 0.35, two or three views per page): bullets, square-bracket prompts and the cue card are where OCR errs.
* Reproduce wording, spelling and punctuation exactly; fix OCR errors only. Keep `[Why?]`-style prompts.
  Exception: C9 is a retyped edition — correct unambiguous typing errors and list each change in `issues`.
* Ignore watermarks / web addresses / page furniture.
* `speaking.json` may carry `"issues": [...]` like the other modules. Do NOT modify listening/reading/writing.json.
* Keep each tool call under ~3 KB of content (the API gateway drops very long responses).
* Finish with a short report: per test the assemble status, the Part 1/3 topic titles and the Part 2 topic.
