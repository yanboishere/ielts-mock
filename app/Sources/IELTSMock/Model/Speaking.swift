import Foundation

/// One answer the candidate recorded in a Speaking test.
struct SpeakingTurn: Codable, Hashable, Identifiable {
    /// "id" (identity check), "p1-0-2" (Part 1, topic 0, question 2), "p1-0-2-why", "p2", "p2-more", "p2-f0", "p3-1-0"
    var id: String
    /// 0 = identity check (not assessed), 1–3 = Part 1–3
    var part: Int
    /// The question as printed (or the examiner's line for prompts such as "Why's that?").
    var question: String
    /// File name inside the attempt's recordings folder.
    var audio: String
    var duration: Double = 0
    var transcript: String?
    /// Where the candidate speaks, from voice activity detection.
    var regions: [SpeechRegion]?

    var assessed: Bool { part > 0 }
    var isFollowUp: Bool { id.hasSuffix("-why") || id.hasSuffix("-more") }
}

struct SpeechRegion: Codable, Hashable {
    var start: Double
    var end: Double
    var length: Double { end - start }
}

/// Delivery measures computed locally from the recordings (voice activity, transcript, pitch).
struct SpeakingMetrics: Codable, Hashable {
    /// Seconds of detected speech in assessed answers.
    var speakingTime: Double
    /// Seconds from the first to the last detected speech of each assessed answer, summed.
    var responseTime: Double
    var words: Int
    /// Words per minute over `responseTime` (pauses included).
    var speechRate: Double
    /// Words per minute of detected speech (pauses excluded).
    var articulationRate: Double
    /// Silent pauses of at least 0.5 s inside answers, per minute of `responseTime`.
    var pausesPerMinute: Double
    /// Silent pauses of 2 s or more inside answers.
    var longPauses: Int
    var meanPause: Double
    /// Mean number of words between pauses of 0.5 s or more.
    var meanLengthOfRun: Double
    /// "um", "uh", "er", "erm", "ah", "hmm" in the transcripts (the recogniser drops some of them).
    var fillers: Int
    var fillersPer100Words: Double
    /// Immediately repeated words ("I I", "the the").
    var repetitions: Int
    /// Mean seconds between the end of a question and the first speech of the answer.
    var meanLatency: Double
    /// Seconds of the Part 2 long turn (0 when Part 2 was not taken).
    var part2Duration: Double
    /// Spread of the voice's pitch in semitones (standard deviation over voiced frames).
    var pitchVariation: Double?
    /// Share of words the spelling dictionary does not know (a rough sign of words the recogniser could not make out).
    var unknownWordRatio: Double
    var pronunciationEstimate: Double
    /// How the estimate was reached, one line per factor, for the result page.
    var pronunciationFactors: [String]
}

struct SpeakingAssessment: Codable, Hashable {
    struct Criterion: Codable, Hashable, Identifiable {
        /// "FC", "LR", "GRA", "P"
        var key: String
        var name: String
        var band: Double
        var comment: String
        var evidence: [String]
        /// Pronunciation is estimated locally rather than judged by the examiner model.
        var estimated: Bool
        var id: String { key }
    }

    struct TurnFeedback: Codable, Hashable, Identifiable {
        var id: String
        var comment: String
        var improved: String
        var corrections: [WritingAssessment.Correction]
    }

    var criteria: [Criterion]
    var overallBand: Double
    var summary: String
    var strengths: [String]
    var improvements: [String]
    var pronunciationNotes: String
    var turns: [TurnFeedback]
    var model: String
    var createdAt: Date

    func feedback(for id: String) -> TurnFeedback? { turns.first { $0.id == id } }
}

struct SpeakingRecord: Codable, Hashable {
    var turns: [SpeakingTurn] = []
    /// Part 2 notes made during the minute of preparation.
    var notes: String = ""
    var metrics: SpeakingMetrics?
    var assessment: SpeakingAssessment?
    /// Recognition model that wrote the transcripts.
    var asrModel: String?

    var assessedTurns: [SpeakingTurn] { turns.filter(\.assessed) }
    var parts: [Int] { Array(Set(assessedTurns.map(\.part))).sorted() }
}

enum SpeakingBand {
    static let criteria: [(key: String, name: String, chinese: String)] = [
        ("FC", "Fluency and Coherence", "流利度与连贯性"),
        ("LR", "Lexical Resource", "词汇丰富度"),
        ("GRA", "Grammatical Range and Accuracy", "语法多样性与准确性"),
        ("P", "Pronunciation", "发音"),
    ]

    /// The Speaking band: the four criteria (whole bands) averaged and rounded as IELTS rounds (x.25 → x.5, x.75 → x+1).
    static func overall(_ bands: [Double]) -> Double? {
        guard bands.count == 4 else { return nil }
        return Grader.overall(bands)
    }

    /// Official public Speaking band descriptors (Fluency and coherence, Lexical resource, Grammatical range and
    /// accuracy, Pronunciation), bands 9 to 0.
    static let descriptors: [String: [Int: String]] = [
        "FC": [
            9: "speaks fluently with only rare repetition or self-correction; any hesitation is content-related rather than to find words or grammar; speaks coherently with fully appropriate cohesive features; develops topics fully and appropriately",
            8: "speaks fluently with only occasional repetition or self-correction; hesitation is usually content-related and only rarely to search for language; develops topics coherently and appropriately",
            7: "speaks at length without noticeable effort or loss of coherence; may demonstrate language-related hesitation at times, or some repetition and/or self-correction; uses a range of connectives and discourse markers with some flexibility",
            6: "is willing to speak at length, though may lose coherence at times due to occasional repetition, self-correction or hesitation; uses a range of connectives and discourse markers but not always appropriately",
            5: "usually maintains flow of speech but uses repetition, self correction and/or slow speech to keep going; may over-use certain connectives and discourse markers; produces simple speech fluently, but more complex communication causes fluency problems",
            4: "cannot respond without noticeable pauses and may speak slowly, with frequent repetition and self-correction; links basic sentences but with repetitious use of simple connectives and some breakdowns in coherence",
            3: "speaks with long pauses; has limited ability to link simple sentences; gives only simple responses and is frequently unable to convey basic message",
            2: "pauses lengthily before most words; little communication possible",
            1: "no communication possible; no rateable language",
            0: "does not attend",
        ],
        "LR": [
            9: "uses vocabulary with full flexibility and precision in all topics; uses idiomatic language naturally and accurately",
            8: "uses a wide vocabulary resource readily and flexibly to convey precise meaning; uses less common and idiomatic vocabulary skilfully, with occasional inaccuracies; uses paraphrase effectively as required",
            7: "uses vocabulary resource flexibly to discuss a variety of topics; uses some less common and idiomatic vocabulary and shows some awareness of style and collocation, with some inappropriate choices; uses paraphrase effectively",
            6: "has a wide enough vocabulary to discuss topics at length and make meaning clear in spite of inappropriacies; generally paraphrases successfully",
            5: "manages to talk about familiar and unfamiliar topics but uses vocabulary with limited flexibility; attempts to use paraphrase but with mixed success",
            4: "is able to talk about familiar topics but can only convey basic meaning on unfamiliar topics and makes frequent errors in word choice; rarely attempts paraphrase",
            3: "uses simple vocabulary to convey personal information; has insufficient vocabulary for less familiar topics",
            2: "only produces isolated words or memorised utterances",
            1: "no communication possible; no rateable language",
            0: "does not attend",
        ],
        "GRA": [
            9: "uses a full range of structures naturally and appropriately; produces consistently accurate structures apart from 'slips' characteristic of native speaker speech",
            8: "uses a wide range of structures flexibly; produces a majority of error-free sentences with only very occasional inappropriacies or basic/non-systematic errors",
            7: "uses a range of complex structures with some flexibility; frequently produces error-free sentences, though some grammatical mistakes persist",
            6: "uses a mix of simple and complex structures, but with limited flexibility; may make frequent mistakes with complex structures though these rarely cause comprehension problems",
            5: "produces basic sentence forms with reasonable accuracy; uses a limited range of more complex structures, but these usually contain errors and may cause some comprehension problems",
            4: "produces basic sentence forms and some correct simple sentences but subordinate structures are rare; errors are frequent and may lead to misunderstanding",
            3: "attempts basic sentence forms but with limited success, or relies on apparently memorised utterances; makes numerous errors except in memorised expressions",
            2: "cannot produce basic sentence forms",
            1: "no communication possible; no rateable language",
            0: "does not attend",
        ],
        "P": [
            9: "uses a full range of pronunciation features with precision and subtlety; sustains flexible use of features throughout; is effortless to understand",
            8: "uses a wide range of pronunciation features; sustains flexible use of features, with only occasional lapses; is easy to understand throughout; L1 accent has minimal effect on intelligibility",
            7: "shows all the positive features of Band 6 and some, but not all, of the positive features of Band 8",
            6: "uses a range of pronunciation features with mixed control; shows some effective use of features but this is not sustained; can generally be understood throughout, though mispronunciation of individual words or sounds reduces clarity at times",
            5: "shows all the positive features of Band 4 and some, but not all, of the positive features of Band 6",
            4: "uses a limited range of pronunciation features; attempts to control features but lapses are frequent; mispronunciations are frequent and cause some difficulty for the listener",
            3: "shows some of the features of Band 2 and some, but not all, of the positive features of Band 4",
            2: "speech is often unintelligible",
            1: "no communication possible; no rateable language",
            0: "does not attend",
        ],
    ]
}
