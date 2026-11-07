import Foundation
import AVFoundation
import Accelerate
import AppKit

/// Delivery measures of a Speaking test from its recordings: voice activity regions, transcripts and pitch.
enum SpeakingAnalysis {
    /// A gap shorter than this between two regions is part of normal articulation, not a pause.
    static let pauseThreshold = 0.5
    static let longPause = 2.0

    static let fillerPattern = #"(?i)\b(u+m+|u+h+|e+r+m*|a+h+|h+m+|m+h*m+)\b"#

    static func words(_ transcript: String) -> [String] {
        let noFillers = transcript.replacingOccurrences(of: fillerPattern, with: " ", options: .regularExpression)
        return noFillers.split { !($0.isLetter || $0.isNumber || $0 == "'" || $0 == "’") }.map(String.init)
    }

    static func fillerCount(_ transcript: String) -> Int {
        (try? NSRegularExpression(pattern: fillerPattern))?.numberOfMatches(in: transcript, range: NSRange(transcript.startIndex..., in: transcript)) ?? 0
    }

    static func repetitions(_ words: [String]) -> Int {
        var n = 0
        for i in 1..<max(1, words.count) where words[i].lowercased() == words[i - 1].lowercased() { n += 1 }
        return n
    }

    struct TurnMeasures {
        var words = 0
        var fillers = 0
        var repetitions = 0
        var speakingTime = 0.0
        var responseTime = 0.0
        var pauses: [Double] = []
        var runs = 0
        var latency: Double?
    }

    static func measure(_ turn: SpeakingTurn) -> TurnMeasures {
        var m = TurnMeasures()
        let t = turn.transcript ?? ""
        let w = words(t)
        m.words = w.count
        m.fillers = fillerCount(t)
        m.repetitions = repetitions(w)
        let regions = (turn.regions ?? []).sorted { $0.start < $1.start }
        guard let first = regions.first, let last = regions.last else { return m }
        m.latency = first.start
        m.responseTime = last.end - first.start
        m.speakingTime = regions.map(\.length).reduce(0, +)
        var runs = 1
        for (a, b) in zip(regions, regions.dropFirst()) {
            let gap = b.start - a.end
            if gap >= pauseThreshold {
                m.pauses.append(gap)
                runs += 1
            }
        }
        m.runs = runs
        return m
    }

    /// Delivery measures of the assessed answers, with the pronunciation estimate.
    @MainActor
    static func metrics(turns: [SpeakingTurn], pitchVariation: Double?) -> SpeakingMetrics {
        let assessed = turns.filter(\.assessed)
        let ms = assessed.map(measure)
        let words = ms.map(\.words).reduce(0, +)
        let speaking = ms.map(\.speakingTime).reduce(0, +)
        let response = ms.map(\.responseTime).reduce(0, +)
        let pauses = ms.flatMap(\.pauses)
        let runs = ms.map(\.runs).reduce(0, +)
        let fillers = ms.map(\.fillers).reduce(0, +)
        let latencies = zip(assessed, ms).filter { !$0.0.id.hasPrefix("p2") }.compactMap(\.1.latency)
        let part2 = zip(assessed, ms).filter { $0.0.id == "p2" || $0.0.id == "p2-more" }.map(\.1.responseTime).reduce(0, +)
        let unknown = unknownWordRatio(assessed.compactMap(\.transcript).joined(separator: " "))
        var m = SpeakingMetrics(
            speakingTime: speaking, responseTime: response, words: words,
            speechRate: response > 0 ? Double(words) / response * 60 : 0,
            articulationRate: speaking > 0 ? Double(words) / speaking * 60 : 0,
            pausesPerMinute: response > 0 ? Double(pauses.count) / response * 60 : 0,
            longPauses: pauses.filter { $0 >= longPause }.count,
            meanPause: pauses.isEmpty ? 0 : pauses.reduce(0, +) / Double(pauses.count),
            meanLengthOfRun: runs > 0 ? Double(words) / Double(runs) : 0,
            fillers: fillers,
            fillersPer100Words: words > 0 ? Double(fillers) / Double(words) * 100 : 0,
            repetitions: ms.map(\.repetitions).reduce(0, +),
            meanLatency: latencies.isEmpty ? 0 : latencies.reduce(0, +) / Double(latencies.count),
            part2Duration: part2,
            pitchVariation: pitchVariation,
            unknownWordRatio: unknown,
            pronunciationEstimate: 0, pronunciationFactors: [])
        let (est, factors) = pronunciation(m)
        m.pronunciationEstimate = est
        m.pronunciationFactors = factors
        return m
    }

    /// A rough Pronunciation band from what the recordings show without a human listener: whether the recogniser
    /// could make out real words, how much the pitch moves, the speed of articulation and how often speech breaks off.
    /// The result page labels it an estimate; `SpeakingAssessment` blends it with the Fluency band.
    static func pronunciation(_ m: SpeakingMetrics) -> (Double, [String]) {
        var score = 6.0
        var f: [String] = []
        let u = m.unknownWordRatio * 100
        switch u {
        case ..<1: score += 0.5; f.append(String(format: "可懂度：识别结果几乎都是正常英语单词（未知词 %.1f%%）  +0.5", u))
        case ..<3: f.append(String(format: "可懂度：少量词未能识别为正常单词（%.1f%%）  ±0", u))
        case ..<6: score -= 0.5; f.append(String(format: "可懂度：较多词未能识别为正常单词（%.1f%%），可能有发音不清的词  −0.5", u))
        default: score -= 1; f.append(String(format: "可懂度：大量词未能识别为正常单词（%.1f%%）  −1", u))
        }
        if let p = m.pitchVariation {
            switch p {
            case ..<1.5: score -= 1; f.append(String(format: "语调：音高变化很小（%.1f 半音），听起来平直单调  −1", p))
            case ..<2.5: score -= 0.5; f.append(String(format: "语调：音高变化偏小（%.1f 半音）  −0.5", p))
            case ..<5.5: score += 0.5; f.append(String(format: "语调：音高起伏自然（%.1f 半音）  +0.5", p))
            default: f.append(String(format: "语调：音高起伏很大（%.1f 半音）  ±0", p))
            }
        } else {
            f.append("语调：录音太短或太安静，无法分析音高  ±0")
        }
        let a = m.articulationRate
        switch a {
        case ..<100: score -= 1; f.append(String(format: "语流：发音速度慢（%.0f 词/分钟，不含停顿），吐字费力  −1", a))
        case ..<130: score -= 0.5; f.append(String(format: "语流：发音速度偏慢（%.0f 词/分钟，不含停顿）  −0.5", a))
        case ..<170: f.append(String(format: "语流：发音速度正常（%.0f 词/分钟，不含停顿）  ±0", a))
        default: score += 0.5; f.append(String(format: "语流：发音流畅连贯（%.0f 词/分钟，不含停顿）  +0.5", a))
        }
        let p = m.pausesPerMinute
        if p > 12 {
            score -= 0.5
            f.append(String(format: "节奏：停顿频繁（每分钟 %.1f 次），意群被切碎  −0.5", p))
        } else if p < 5, m.responseTime > 0 {
            score += 0.5
            f.append(String(format: "节奏：停顿少（每分钟 %.1f 次），意群完整  +0.5", p))
        } else {
            f.append(String(format: "节奏：停顿频率正常（每分钟 %.1f 次）  ±0", p))
        }
        return (min(8.5, max(2, score)), f)
    }

    /// Share of words the system spelling dictionary rejects. Proper nouns (capitalised words other than "I") and
    /// words shorter than three letters are left out.
    @MainActor
    static func unknownWordRatio(_ text: String) -> Double {
        let checker = NSSpellChecker.shared
        let ws = words(text).filter { w in
            guard w.count >= 3, let c = w.first, !c.isUppercase else { return false }
            return w.allSatisfy { $0.isLetter || $0 == "'" || $0 == "’" }
        }
        guard !ws.isEmpty else { return 0 }
        var unknown = 0
        for w in ws {
            let r = checker.checkSpelling(of: w, startingAt: 0, language: "en", wrap: false, inSpellDocumentWithTag: 0, wordCount: nil)
            if r.location != NSNotFound { unknown += 1 }
        }
        return Double(unknown) / Double(ws.count)
    }

    /// Standard deviation of the voice's pitch in semitones, over voiced frames inside the speech regions.
    static func pitchVariation(files: [(URL, [SpeechRegion])]) -> Double? {
        var semis: [Double] = []
        var all: [Float] = []
        for (url, regions) in files {
            guard let (samples, rate) = try? floatSamples(url) else { continue }
            all.append(contentsOf: f0s(samples: samples, rate: rate, regions: regions))
        }
        guard all.count >= 50 else { return nil }
        let sorted = all.sorted()
        let median = Double(sorted[sorted.count / 2])
        for f in all {
            let s = 12 * log2(Double(f) / median)
            // Octave errors of the tracker.
            if abs(s) < 12 { semis.append(s) }
        }
        guard semis.count >= 50 else { return nil }
        let mean = semis.reduce(0, +) / Double(semis.count)
        let v = semis.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(semis.count)
        return sqrt(v)
    }

    private static func floatSamples(_ url: URL) throws -> ([Float], Double) {
        let file = try AVAudioFile(forReading: url)
        let fmt = file.processingFormat
        guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(file.length)) else { return ([], fmt.sampleRate) }
        try file.read(into: buf)
        guard let ch = buf.floatChannelData else { return ([], fmt.sampleRate) }
        return (Array(UnsafeBufferPointer(start: ch[0], count: Int(buf.frameLength))), fmt.sampleRate)
    }

    /// Normalised autocorrelation pitch tracker: 40 ms frames every 20 ms, 75–400 Hz, voiced when the peak
    /// correlation exceeds 0.6 and the frame is not near silence.
    static func f0s(samples: [Float], rate: Double, regions: [SpeechRegion]) -> [Float] {
        let frame = Int(rate * 0.04)
        let hop = Int(rate * 0.02)
        let minLag = Int(rate / 400)
        let maxLag = Int(rate / 75)
        let window = frame - maxLag
        guard window > minLag, samples.count > frame else { return [] }
        var out: [Float] = []
        var corr = [Float](repeating: 0, count: maxLag + 1)
        for r in regions {
            var start = max(0, Int(r.start * rate))
            let end = min(samples.count - frame, Int(r.end * rate))
            while start < end {
                samples.withUnsafeBufferPointer { p in
                    let base = p.baseAddress! + start
                    var energy: Float = 0
                    vDSP_svesq(base, 1, &energy, vDSP_Length(window))
                    guard energy / Float(window) > 1e-5 else { return }
                    vDSP_conv(base, 1, base, 1, &corr, 1, vDSP_Length(maxLag + 1), vDSP_Length(window))
                    var best: Float = 0
                    var lag = 0
                    for l in minLag...maxLag {
                        var e2: Float = 0
                        vDSP_svesq(base + l, 1, &e2, vDSP_Length(window))
                        let n = corr[l] / max(1e-9, sqrt(energy * e2))
                        if n > best {
                            best = n
                            lag = l
                        }
                    }
                    if best > 0.6, lag > 0 { out.append(Float(rate) / Float(lag)) }
                }
                start += hop
            }
        }
        return out
    }
}
