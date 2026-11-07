import Foundation

extension Prompts {
    static func speakingSystem(language: String) -> String {
        func table(_ key: String) -> String {
            (SpeakingBand.descriptors[key] ?? [:]).sorted { $0.key > $1.key }.map { "  Band \($0.key): \($0.value)" }.joined(separator: "\n")
        }
        return """
        You are a senior, certified IELTS Speaking examiner. Rate the candidate's performance in this Speaking test on three of the four official criteria, using the public IELTS Speaking band descriptors below:

        Fluency and Coherence
        \(table("FC"))

        Lexical Resource
        \(table("LR"))

        Grammatical Range and Accuracy
        \(table("GRA"))

        Pronunciation (for reference only — the app measures it from the audio; do NOT give a pronunciation band)
        \(table("P"))

        How to rate:
        - Award a whole band (0–9) for each criterion, as IELTS examiners do. A band is awarded when the performance fits that band's descriptor better than the neighbouring ones. Be calibrated like a real examiner; do not inflate scores.
        - Base the rating on the whole test. Consider length and development of answers (very short Part 1/Part 3 answers and a Part 2 long turn well under one minute limit the evidence for higher bands), relevance to the question, and whether answers sound memorised.
        - The transcripts were written by an automatic speech recogniser: punctuation and capitalisation are automatic, some hesitation fillers ("um", "er") may be missing, and a few words may be misrecognised. Do not penalise grammar or vocabulary for errors that are plausibly recognition errors. The recogniser's language model also silently corrects some small slips (for example "someone enjoy" written as "someone enjoys"), so a clean transcript is not proof of fully accurate grammar: do not award the top Grammatical Range and Accuracy bands on the transcript's surface accuracy alone. Judge the delivery side of Fluency and Coherence mainly from the measured timing data (pauses, speaking rate, length of runs, latency), which is accurate.
        - Quote the candidate's exact words from the transcripts in `evidence` and in `original`.
        - In `pronunciation_notes`, mention only what the transcript can suggest (for example words that look misrecognised and may have been mispronounced); say plainly that pronunciation cannot be judged reliably from a transcript.
        - For every answer id listed, give `comment` (what worked and the most useful change), `improved` (a natural, high-band answer to the same question that keeps the candidate's ideas: 2–5 sentences for Part 1 and Part 3, about 200–250 words for the Part 2 long turn; for short follow-up prompts 1–3 sentences) and up to 3 `corrections` of real language errors (empty when there are none).
        Write `comment`, `summary`, `strengths`, `improvements`, `explanation` and `pronunciation_notes` in \(languageName(language)). Write `improved` and `suggestion` in English.
        """
    }

    static func speakingUser(exam: Exam, record: SpeakingRecord, metrics: SpeakingMetrics?, practicePart: Int?) -> String {
        var s = "# \(exam.title) — Speaking"
        if let p = practicePart { s += " (Part \(p) practised on its own; rate on this evidence only)" }
        s += "\n"
        if let c = exam.speaking?.part2, record.parts.contains(2) {
            s += "\nPart 2 cue card: \(InlineMarkup.strip(c.topic)) \(c.prompt ?? "") "
            s += c.points.map { "• \($0)" }.joined(separator: " ") + " \(c.closing ?? "")\n"
        }
        if !record.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            s += "Candidate's preparation notes: \(record.notes)\n"
        }
        s += "\n# Answers\n"
        for t in record.assessedTurns {
            let m = SpeakingAnalysis.measure(t)
            s += "\n[\(t.id)] Part \(t.part)\(t.isFollowUp ? " (examiner's follow-up)" : "") — Q: \(InlineMarkup.strip(t.question))\n"
            if m.responseTime > 0 {
                s += String(format: "Timing: recorded %.1f s; started speaking after %.1f s; %.1f s of speech; %d %@ ≥0.5 s",
                            t.duration, m.latency ?? 0, m.speakingTime, m.pauses.count, m.pauses.count == 1 ? "pause" : "pauses")
                if let longest = m.pauses.max() { s += String(format: " (longest %.1f s)", longest) }
                s += "; \(m.words) words.\n"
            } else {
                s += String(format: "Timing: recorded %.1f s; no speech detected.\n", t.duration)
            }
            let tr = (t.transcript ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            s += "Transcript: \(tr.isEmpty ? "(no speech recognised)" : tr)\n"
        }
        if let m = metrics {
            s += "\n# Measured delivery (whole test)\n"
            s += String(format: """
            - Speaking time %.0f s over %.0f s of answering; %d words
            - Speech rate %.0f words/min including pauses (fluent speakers typically 120–170); articulation rate %.0f words/min excluding pauses
            - %.1f pauses ≥0.5 s per minute (fluent speech typically under 8); %d pause(s) of 2 s or more; mean pause %.1f s
            - Mean length of run %.1f words between pauses
            - Fillers recognised: %d (%.1f per 100 words; the recogniser drops some)
            - Immediate word repetitions: %d
            - Mean delay before answering: %.1f s
            """, m.speakingTime, m.responseTime, m.words, m.speechRate, m.articulationRate, m.pausesPerMinute, m.longPauses,
                   m.meanPause, m.meanLengthOfRun, m.fillers, m.fillersPer100Words, m.repetitions, m.meanLatency)
            if m.part2Duration > 0 { s += String(format: "\n- Part 2 long turn: %.0f s (the task asks for one to two minutes)", m.part2Duration) }
            s += "\n"
        }
        return s
    }

    static var speakingSchema: [String: Any] {
        let criterion: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "required": ["band", "comment", "evidence"],
            "properties": [
                "band": ["type": "integer", "description": "whole band 0–9"],
                "comment": ["type": "string"],
                "evidence": ["type": "array", "items": ["type": "string"], "description": "short quotes from the transcripts"],
            ],
        ]
        return [
            "type": "object",
            "additionalProperties": false,
            "required": ["fluency_coherence", "lexical_resource", "grammatical_range", "pronunciation_notes", "summary", "strengths", "improvements", "answers"],
            "properties": [
                "fluency_coherence": criterion,
                "lexical_resource": criterion,
                "grammatical_range": criterion,
                "pronunciation_notes": ["type": "string"],
                "summary": ["type": "string"],
                "strengths": ["type": "array", "items": ["type": "string"]],
                "improvements": ["type": "array", "items": ["type": "string"]],
                "answers": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "additionalProperties": false,
                        "required": ["id", "comment", "improved", "corrections"],
                        "properties": [
                            "id": ["type": "string"],
                            "comment": ["type": "string"],
                            "improved": ["type": "string"],
                            "corrections": [
                                "type": "array",
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
                        ],
                    ],
                ],
            ],
        ]
    }
}

extension AIService {
    /// Rates Fluency and Coherence, Lexical Resource and Grammatical Range and Accuracy with the examiner model;
    /// Pronunciation is the local estimate blended with Fluency (both whole bands, as IELTS awards them).
    func assessSpeaking(ref: ExamRef, record: SpeakingRecord, practicePart: Int?) async throws -> SpeakingAssessment {
        let system = Prompts.speakingSystem(language: settings.aiLanguage)
        let user = Prompts.speakingUser(exam: ref.exam, record: record, metrics: record.metrics, practicePart: practicePart)
        let effort = settings.writingEffort
        let key = "speaking-\(ref.exam.id)"
        return try await run(key) { c, p in
            let req = LLMRequest(system: system, content: [.text(user)], schema: Prompts.speakingSchema,
                                 schemaName: "ielts_speaking_assessment", maxTokens: 48000, effort: effort)
            let r = try await c.complete(req, progress: p)
            guard let d = extractJSONObject(r.text).data(using: .utf8),
                  let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else {
                throw AIError.badResponse(String(r.text.prefix(300)))
            }
            func band(_ v: Any?) -> Double {
                let x = (v as? Double) ?? Double(v as? Int ?? 0)
                return min(9, max(0, x.rounded()))
            }
            func criterion(_ key: String, _ field: String, _ name: String) -> SpeakingAssessment.Criterion {
                let o = j[field] as? [String: Any] ?? [:]
                return .init(key: key, name: name, band: band(o["band"]), comment: o["comment"] as? String ?? "",
                             evidence: o["evidence"] as? [String] ?? [], estimated: false)
            }
            let fc = criterion("FC", "fluency_coherence", "Fluency and Coherence")
            let lr = criterion("LR", "lexical_resource", "Lexical Resource")
            let gra = criterion("GRA", "grammatical_range", "Grammatical Range and Accuracy")
            let estimate = record.metrics?.pronunciationEstimate ?? fc.band
            let pBand = min(9, max(0, ((estimate + fc.band) / 2).rounded(.toNearestOrAwayFromZero)))
            var pComment = "根据录音的可懂度、语调起伏、发音速度与停顿节奏估算（\(Grader.bandString(estimate))），并与流利度分数综合，取整为 \(Int(pBand)) 分。发音无法仅凭文字与声学指标准确判断，仅供参考。"
            if let factors = record.metrics?.pronunciationFactors, !factors.isEmpty { pComment += "\n" + factors.map { "• " + $0 }.joined(separator: "\n") }
            let pron = SpeakingAssessment.Criterion(key: "P", name: "Pronunciation", band: pBand, comment: pComment, evidence: [], estimated: true)
            let criteria = [fc, lr, gra, pron]
            let turns = (j["answers"] as? [[String: Any]] ?? []).map { a in
                SpeakingAssessment.TurnFeedback(
                    id: a["id"] as? String ?? "", comment: a["comment"] as? String ?? "", improved: a["improved"] as? String ?? "",
                    corrections: (a["corrections"] as? [[String: Any]] ?? []).map {
                        WritingAssessment.Correction(original: $0["original"] as? String ?? "", suggestion: $0["suggestion"] as? String ?? "",
                                                     explanation: $0["explanation"] as? String ?? "")
                    })
            }
            return SpeakingAssessment(
                criteria: criteria, overallBand: SpeakingBand.overall(criteria.map(\.band)) ?? 0,
                summary: j["summary"] as? String ?? "", strengths: j["strengths"] as? [String] ?? [],
                improvements: j["improvements"] as? [String] ?? [], pronunciationNotes: j["pronunciation_notes"] as? String ?? "",
                turns: turns, model: r.model, createdAt: Date())
        }
    }
}
