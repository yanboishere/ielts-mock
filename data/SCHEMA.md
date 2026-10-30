# IELTS Mock exam JSON — schema `ielts-mock.exam/1`

One file per test: `~/ielts-data/bank/exams/C{book}-T{test}.json` (e.g. `C15-T1.json`, Cambridge 12 uses T5–T8).
The app renders everything from this file, so it must be **faithful to the printed book** (wording, numbering,
spelling, punctuation) with OCR errors fixed. Never invent or "improve" content. Use straight ASCII quotes `'` `"` and
the en dash `–` in number ranges like the book ("Questions 1–10").

```jsonc
{
  "schema": "ielts-mock.exam/1",
  "id": "C15-T1",
  "source": { "book": 15, "test": 1 },
  "title": "Cambridge IELTS 15 · Test 1",
  "issues": [],                      // optional: free-text notes about anything you could not reproduce faithfully
  "listening": { "parts": [Part, Part, Part, Part], "answers": Answers },
  "reading":   { "passages": [Passage, Passage, Passage], "answers": Answers },
  "writing":   { "tasks": [Task1, Task2] }
}
```

## Inline text markup
All display strings may use light markdown: `**bold**`, `*italic*`. Use it where the book uses bold/italic
(instructions like `Write **ONE WORD AND/OR A NUMBER** for each answer.`, titles in italics, etc.).
Inside completion content, a gap for question *n* is written `{{n}}` — e.g. `"Name of agent: Becky {{1}}"`.
Every question number of a completion group must appear exactly once as a gap. Do not leave dotted lines
(`.........`) or underscores in the text — the gap marker replaces them.

## Listening part
```jsonc
{
  "part": 1,                         // 1..4 (older books say SECTION 1..4 — still use "part")
  "range": [1, 10],                  // always [1,10], [11,20], [21,30], [31,40]
  "pages": [12, 13],                 // source PDF page numbers (1-based, as used by the `ielts` tool)
  "context": "You will hear a woman talking to a recruitment agent.",   // optional, only if printed (rare)
  "groups": [Group, ...],
  "transcript": "AMBER: Hello, is that William?\nWILLIAM: Yes ...\n..."  // full audioscript of this part
}
```
Transcript rules: one speaker turn (or monologue paragraph) per line, speaker label in CAPITALS followed by `: `
exactly as printed (`MAN:`, `RECEPTIONIST:`). Monologues have no labels. Keep the book's answer-location markers
as `[Q7]` at the position where they are printed (books from C13 on print `Q7` in the margin — put `[Q7]` at the
end of that line/sentence). Skip page headers/footers/page numbers. Do not include the "Example" announcement
lines differently — keep them as printed.

## Reading passage
```jsonc
{
  "passage": 1,
  "range": [1, 13],                  // passages are contiguous and cover 1..40 (e.g. 1–13, 14–26, 27–40)
  "pages": [18, 19, 20, 21],
  "intro": "You should spend about 20 minutes on **Questions 1–13**, which are based on Reading Passage 1 below.",
  "title": "Nutmeg – a valuable spice",
  "subtitle": null,                  // optional standfirst/sub-title printed under the title (italic line), else null
  "paragraphs": [
    { "label": "A", "text": "The nutmeg tree, *Myristica fragrans*, is a large evergreen tree native to ..." },
    { "kind": "heading", "text": "The history of nutmeg" },          // in-passage sub-heading (no label)
    { "text": "Paragraph without a letter ..." },
    { "kind": "note", "text": "* *Bactrian* – an ancient region ..." }, // footnote / glossary printed under the passage
    { "kind": "img", "src": "images/C15/C15-T1-R1-fig.png", "text": "Figure caption or empty" }
  ],
  "groups": [Group, ...]
}
```
Paragraph rules: one object per printed paragraph; join the lines of a paragraph into one string, remove
end-of-line hyphenation (`envi-\nronment` → `environment`) but keep real hyphens (`well-known`).
If the book letters paragraphs/sections (A, B, C…), put the letter in `label` and not in `text`.

## Question groups
Every group has:
```jsonc
{
  "id": "L1-1",                      // unique inside the file: L{part}-{k} / R{passage}-{k}
  "type": "completion" | "choice" | "multi" | "tfng" | "ynng" | "matching",
  "range": [1, 10],                  // first and last question number in this group
  "instructions": ["Complete the notes below.", "Write **ONE WORD AND/OR A NUMBER** for each answer."],
  "title": "Matthews Island Holidays",   // optional centred heading printed above choice/matching questions
  "image": "images/C15/C15-T2-L2-map.png" // optional figure belonging to the group (map, plan, diagram, flow chart)
}
```
`instructions` = the printed rubric lines under "Questions x–y" (not the "Questions x–y" line itself), one string per
line/sentence. Drop "In boxes 1–5 on your answer sheet" style phrases? **No — keep them exactly as printed**; the app
shows them as in the book.

### `completion` — notes / form / table / flow-chart / sentence / summary / diagram labels / short answers
```jsonc
{
  "type": "completion", "range": [1, 10], "instructions": [...],
  "content": [
    { "t": "h",   "text": "Bankside Recruitment Agency" },      // title of the notes/form/table
    { "t": "sub", "text": "Typical jobs" },                     // bold sub-heading
    { "t": "li",  "text": "Address of agency: 497 Eastside, Docklands" },   // bullet line (level: 2 for nested)
    { "t": "li",  "text": "Name of agent: Becky {{1}}" },
    { "t": "p",   "text": "Plain line / sentence / summary paragraph with {{5}} gaps" },
    { "t": "note","text": "*Example* ... or other small print" },
    { "t": "table", "rows": [["", "Activity", "Notes"],
                              ["Day 1", "Arrive", "Introduction by manager\nHotel dining room has view of the {{15}}"]],
      "header": 1 },                                            // number of header rows; cells may contain \n
    { "t": "flow", "steps": ["Step one text {{31}}", "Step two ..."] },  // vertical flow chart boxes
    { "t": "img",  "src": "images/C15/xxx.png" }                // a figure inside the content
  ],
  "options": [ { "key": "A", "text": "safety" }, ... ],         // ONLY when answers are letters chosen from a box/list
  "optionsTitle": "List of words"                               // optional title of that box
}
```
* Indentation: `li`, `p` and `note` blocks take an optional `"level"` (1 = default, 2, 3) for nested bullets /
  indented continuation lines (e.g. `{ "t": "p", "level": 3, "text": "– trees were unable to take in necessary iron" }`).
  Keep printed list markers that are part of the text, e.g. `"A) Diseases"`, `"(i) 'Mundulla Yellows'"`, `"– make more {{36}} available"`.
* Sentence completion: one `p` block per numbered sentence; keep the sentence text and put `{{n}}` where the gap is.
  The app shows the number in the gap, so do not also write the number before the sentence.
* Short-answer questions ("Answer the questions below"): one `p` per question: `"What was the original purpose of the building? {{14}}"`.
* Diagram/plan labelling with words: put the diagram in group `image` (crop it — the printed numbers stay
  visible on the picture) and list one `p` per gap with any printed label text, e.g. `"{{21}} for storing food"` or just `"{{21}}"`.
* Summary completion with a list of words/phrases A–I: normal `p` content with gaps **plus** `options`; answers are letters.
* Flow charts: prefer `flow` blocks; if the layout is too graphical, crop it as group `image` and list the gaps as `p` lines.

### `choice` — one correct letter per question
```jsonc
{ "type": "choice", "range": [11, 14], "instructions": ["Choose the correct letter, **A**, **B** or **C**."],
  "title": "Matthews Island Holidays",
  "questions": [ { "n": 11, "text": "According to the speaker, the company",
                   "options": [ {"key":"A","text":"has been in business for longer than most of its competitors."}, ... ] } ] }
```

### `multi` — choose TWO/THREE letters for a set of question numbers (marked in either order)
```jsonc
{ "type": "multi", "range": [21, 22], "n": [21, 22], "select": 2,
  "instructions": ["Choose **TWO** letters, **A–E**."],
  "text": "Which TWO activities are included in the price of the holiday?",
  "options": [ {"key":"A","text":"..."}, ... ] }
```
Answers: put one letter per question number (`"21": {"a":["B"]}, "22": {"a":["D"]}`) — order does not matter.

### `tfng` / `ynng`
```jsonc
{ "type": "tfng", "range": [5, 7], "instructions": ["Do the following statements agree with the information given in Reading Passage 1?", "In boxes 5–7 on your answer sheet, write", "**TRUE** if the statement agrees with the information", "**FALSE** if the statement contradicts the information", "**NOT GIVEN** if there is no information on this"],
  "questions": [ { "n": 5, "text": "In the 16th century, ..." } ] }
```
Answers are exactly `TRUE` / `FALSE` / `NOT GIVEN` (or `YES` / `NO` / `NOT GIVEN`).

### `matching` — headings, paragraph information, features, sentence endings, map/plan letters, classification
```jsonc
{ "type": "matching", "range": [14, 18],
  "instructions": ["Reading Passage 2 has seven sections, **A–G**.", "Which section contains the following information?", "Write the correct letter, **A–G**, in boxes 14–18 on your answer sheet."],
  "optionsTitle": "List of Headings",          // optional box title as printed
  "options": [ {"key":"A","text":""}, {"key":"B","text":""}, ... ],  // paragraph/section letters: empty text
  "reuse": true,                               // true when printed "NB You may use any letter more than once"
  "questions": [ { "n": 14, "text": "a reference to ..." } ] }
```
* Matching headings: options keys are roman numerals as printed (`"i"`, `"ii"`, …, lower case); questions are
  `"Paragraph B"` / `"Section C"`. If the book shows a worked example (e.g. "Example Paragraph A … Answer v"), add it as an
  extra instruction line: `"Example: Paragraph A – v"`.
* Map/plan labelling with letters: group `image` = the map; options = the letters with empty text; questions = place names.
* Sentence endings: questions = sentence beginnings, options = endings.

## Answers
`answers` maps every question number "1".."40" to `{ "a": [accepted answers...], "k": "key as printed" }`.
* Expand the key notation into **all** accepted strings: `grass(es)` → `["grass", "grasses"]`;
  `(unique) expeditions` → `["unique expeditions", "expeditions"]`; `10/ten` → `["10", "ten"]`;
  `car (-) sharing` → `["car sharing", "car-sharing"]`; `uncontacted / isolated` → `["uncontacted", "isolated"]`.
  Put the printed form in `k` (omit `k` when it is identical to the only accepted answer).
* Letters: `{"a": ["C"]}`; roman numerals as printed in lower case `{"a": ["iv"]}`; TFNG/YNNG in capitals.
* `IN EITHER ORDER` pairs of letters → use a `multi` group. If two **word** gaps are "in either order",
  add `"eitherOrder": [[33, 34]]` to the module object (next to `answers`).
* When the key says both words are needed for one mark (e.g. "BOTH required"), list the full answer strings in the
  accepted forms (e.g. `["sight and hearing", "hearing and sight"]`).

## Writing tasks
```jsonc
{ "task": 1, "minutes": 20, "minWords": 150, "pages": [30],
  "prompt": ["The chart below shows the results of a survey about people's coffee and tea buying and drinking habits in five Australian cities.",
             "Summarise the information by selecting and reporting the main features, and make comparisons where relevant."],
  "image": "images/C15/C15-T1-W1.png",
  "sample": { "kind": "candidate", "band": "6.5", "text": "full sample answer text", "comment": "examiner comment" } }
{ "task": 2, "minutes": 40, "minWords": 250, "pages": [31],
  "prompt": ["Write about the following topic:", "*In some countries, ...*", "Discuss both these views and give your own opinion.", "Give reasons for your answer and include any relevant examples from your own knowledge or experience."] }
```
`prompt` = the boxed task text (not "You should spend about…" and not "Write at least … words."). Keep the
"Write about the following topic:" line for Task 2. `sample` is optional: include the book's sample/model answer for
that task when the book has one (`kind`: `"candidate"` for "answer written by a candidate", `"model"` for a model
answer), with its band score (string, or null) and the examiner comment (or null).

## Images
Crop figures with `ielts figcrop BOOK PAGE x y w h NAME` (normalized, top-left origin) and use the printed JSON path.
Naming: `C15-T1-L2-map`, `C15-T1-L4-diagram`, `C15-T1-R2-diagram`, `C15-T1-W1`. Include the figure's own printed
title/legend/axes inside the crop, exclude the question list, page headers and the QR-code watermark.
Verify every crop by viewing it.
