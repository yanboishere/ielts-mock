import Foundation

enum Prompts {
    static func languageName(_ code: String) -> String { code == "en" ? "English" : "Simplified Chinese (简体中文)" }

    // MARK: question rendering (plain text, as the student saw it)

    static func render(group g: QuestionGroup, showNumbersOnly: Set<Int>? = nil) -> String {
        var out: [String] = [g.heading]
        out += g.instructions.map { InlineMarkup.strip($0) }
        if let t = g.title { out.append(InlineMarkup.strip(t)) }
        if g.image != nil { out.append("[The question includes a picture/diagram/map, not shown here.]") }
        func gaps(_ s: String) -> String { QuestionGroup.blankGaps(InlineMarkup.strip(s), highlight: nil).replacingOccurrences(of: "(", with: "(Q") }
        for b in g.content ?? [] {
            switch b.t {
            case "table":
                for row in b.rows ?? [] { out.append("| " + row.map { gaps($0).replacingOccurrences(of: "\n", with: " / ") }.joined(separator: " | ") + " |") }
            case "flow":
                for s in b.steps ?? [] { out.append("→ " + gaps(s)) }
            case "img":
                out.append("[picture]")
            default:
                if let t = b.text { out.append(String(repeating: "  ", count: max(0, (b.level ?? 1) - 1)) + (b.t == "li" ? "• " : "") + gaps(t)) }
            }
        }
        if g.type == .multi {
            out.append("Q\(g.numbers.rangeLabel): " + InlineMarkup.strip(g.text ?? ""))
        }
        if let opts = g.options, g.type != .choice {
            if let t = g.optionsTitle { out.append(t) }
            for o in opts where !o.text.isEmpty { out.append("\(o.key)  \(InlineMarkup.strip(o.text))") }
            if opts.allSatisfy({ $0.text.isEmpty }) { out.append("Options: " + opts.map(\.key).joined(separator: ", ")) }
        }
        for q in g.questions ?? [] {
            out.append("Q\(q.n). \(InlineMarkup.strip(q.text))")
            for o in q.options ?? [] { out.append("   \(o.key)  \(InlineMarkup.strip(o.text))") }
        }
        return out.joined(separator: "\n")
    }

    // MARK: explanations

    static let explanationSchema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "required": ["items"],
        "properties": [
            "items": [
                "type": "array",
                "items": [
                    "type": "object",
                    "additionalProperties": false,
                    "required": ["number", "explanation", "evidence", "paraphrases", "tip"],
                    "properties": [
                        "number": ["type": "integer", "description": "question number"],
                        "explanation": ["type": "string", "description": "why the key is right and why the student's answer is wrong (markdown allowed)"],
                        "evidence": ["type": "string", "description": "the exact sentence(s) copied verbatim from the passage/transcript that locate the answer"],
                        "paraphrases": ["type": "array", "items": ["type": "string"], "description": "synonym/paraphrase pairs between the question wording and the text, formatted 'question wording ⇄ text wording'"],
                        "tip": ["type": "string", "description": "one short actionable tip for this question type"],
                    ],
                ],
            ],
        ],
    ]

    static func explanationSystem(language: String) -> String {
        """
        You are an experienced IELTS teacher who explains Cambridge IELTS practice-test answers to a Chinese candidate.
        For every question the student got wrong, explain clearly and concretely:
        1. Where the answer is located (quote the exact sentence from the source text in `evidence`, copied verbatim so it can be highlighted).
        2. Why the official key is correct, pointing out the paraphrase / synonym relationship between the question and the text.
        3. Why the student's answer is wrong (e.g. distractor, misread negation, wrong word form, spelling, word limit, NOT GIVEN vs FALSE logic). If the student left it blank, say what they should have listened/looked for.
        The official answer key is always authoritative — never argue with it.
        Keep each explanation focused (about 80–180 words). Write `explanation` and `tip` in \(languageName(language)); keep quotes in English.
        """
    }

    static func explanationUser(sourceTitle: String, sourceText: String, groups: [QuestionGroup], wrong: [QuestionResult], isListening: Bool) -> String {
        var s = ""
        s += isListening ? "# Listening audioscript — \(sourceTitle)\n" : "# Reading passage — \(sourceTitle)\n"
        s += sourceText + "\n\n"
        s += "# Questions as printed\n"
        s += groups.map { render(group: $0) }.joined(separator: "\n\n")
        s += "\n\n# The student's wrong answers\n"
        for r in wrong {
            let user = r.isBlank ? "(left blank)" : "\"\(r.user)\""
            s += "Q\(r.number) [\(r.type.rawValue)]: student answered \(user); official key: \(r.keyDisplay)"
            if r.accepted.count > 1 { s += " (accepted: \(r.accepted.joined(separator: " / ")))" }
            if r.nearMiss { s += " — the student's answer is very close (spelling/plural/hyphen); point out the exact difference" }
            s += "\n"
        }
        s += "\nReturn one item per question listed above, in the same order."
        return s
    }

    // MARK: writing

    static let writingSchema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "required": ["overall_band", "criteria", "summary", "strengths", "weaknesses", "corrections", "improved_version", "next_steps"],
        "properties": [
            "overall_band": ["type": "number", "description": "overall band for this task, a multiple of 0.5 between 0 and 9"],
            "criteria": [
                "type": "array",
                "description": "exactly four criteria in the official order",
                "items": [
                    "type": "object",
                    "additionalProperties": false,
                    "required": ["name", "band", "comment"],
                    "properties": [
                        "name": ["type": "string", "enum": ["Task Achievement", "Task Response", "Coherence and Cohesion", "Lexical Resource", "Grammatical Range and Accuracy"]],
                        "band": ["type": "number"],
                        "comment": ["type": "string"],
                    ],
                ],
            ],
            "summary": ["type": "string"],
            "strengths": ["type": "array", "items": ["type": "string"]],
            "weaknesses": ["type": "array", "items": ["type": "string"]],
            "corrections": [
                "type": "array",
                "description": "the most important language errors, quoted exactly from the essay",
                "items": [
                    "type": "object",
                    "additionalProperties": false,
                    "required": ["original", "suggestion", "explanation"],
                    "properties": [
                        "original": ["type": "string"],
                        "suggestion": ["type": "string"],
                        "explanation": ["type": "string"],
                    ],
                ],
            ],
            "improved_version": ["type": "string", "description": "a revised version of the student's essay at about Band 7.5–8, keeping the student's ideas and structure"],
            "next_steps": ["type": "array", "items": ["type": "string"]],
        ],
    ]

    static func writingSystem(language: String, task: Int) -> String {
        """
        You are a senior, certified IELTS Academic Writing examiner. Assess the candidate's Writing Task \(task) response strictly against the public IELTS Writing band descriptors:
        \(task == 1 ? "Task Achievement" : "Task Response"), Coherence and Cohesion, Lexical Resource, Grammatical Range and Accuracy (each 0–9 in half bands).
        Be calibrated like a real examiner — do not inflate scores. Apply the usual penalties: under length (fewer than \(task == 1 ? 150 : 250) words), missing overview (Task 1), not answering all parts of the question (Task 2), irrelevant or memorised material, copied wording from the prompt, unclear position.
        The overall task band is the mean of the four criteria rounded down to the nearest half band unless clearly justified.
        For `corrections`, quote the student's exact words in `original` (max 12 items, most important first).
        Write `comment`, `summary`, `strengths`, `weaknesses`, `explanation` and `next_steps` in \(languageName(language)). Write `improved_version` and `suggestion` in English.
        """
    }

    static func writingUser(task: WritingTask, essay: String, wordCount: Int, includeSample: Bool) -> String {
        var s = "# Writing Task \(task.task) (Academic)\n"
        s += task.prompt.map { InlineMarkup.strip($0) }.joined(separator: "\n")
        s += "\n\nWrite at least \(task.minWords) words. Suggested time: \(task.minutes) minutes.\n"
        if task.image != nil { s += "(The task's chart/diagram is attached as an image.)\n" }
        if includeSample, let sample = task.sample {
            s += "\n# Calibration reference (from the official book — do not grade this)\n"
            s += "A \(sample.kind == "model" ? "model answer" : "candidate answer")" + (sample.band.map { " rated Band \($0)" } ?? "") + ":\n"
            s += sample.text + "\n"
            if let c = sample.comment { s += "Examiner comment: \(c)\n" }
        }
        s += "\n# Candidate's response (\(wordCount) words)\n"
        s += essay.isEmpty ? "(empty)" : essay
        return s
    }
}
