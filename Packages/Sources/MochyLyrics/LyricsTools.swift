import Foundation
import MochyCore

// MARK: - Zero-Bloat Romanization via Apple CFStringTransform

public enum LyricsRomanizer {
    /// Romanizes Japanese, Chinese, Korean, Russian/Cyrillic, Hindi/Devanagari, and Arabic lines using CoreFoundation.
    public static func romanize(_ text: String) -> String {
        let mutable = NSMutableString(string: text) as CFMutableString
        CFStringTransform(mutable, nil, kCFStringTransformToLatin, false)
        CFStringTransform(mutable, nil, kCFStringTransformStripCombiningMarks, false)
        return (mutable as String).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func romanizedDocument(_ doc: LyricsDocument) -> LyricsDocument {
        let updated = doc.lines.map { line -> LyricsLine in
            var copy = line
            let script = ScriptDetector.detect(line.text)
            if script != .latin && script != .unknown {
                copy.romanized = romanize(line.text)
            }
            return copy
        }
        return LyricsDocument(
            sourceProvider: doc.sourceProvider,
            lines: updated,
            isSynced: doc.isSynced,
            isWordTimed: doc.isWordTimed,
            hasDuet: doc.hasDuet,
            hasBackgroundVocals: doc.hasBackgroundVocals,
            isSyllableSplit: doc.isSyllableSplit,
            script: doc.script
        )
    }
}

// MARK: - Multi-Backend Lyrics Translator

public enum LyricsTranslationBackend: String, CaseIterable, Codable, Sendable {
    case google
    case deepl
    case openrouter
}

public actor LyricsTranslator {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func translate(
        document: LyricsDocument,
        targetLanguage: String,
        backend: LyricsTranslationBackend = .google
    ) async -> LyricsDocument {
        let texts = document.lines.map(\.text)
        guard !texts.isEmpty else { return document }

        let translatedLines: [String]
        switch backend {
        case .google:
            translatedLines = await translateWithGoogle(lines: texts, targetLanguage: targetLanguage)
        case .deepl, .openrouter:
            if let key = SecretVault.get(.aiApiKey), !key.isEmpty {
                translatedLines = await translateWithOpenRouter(
                    lines: texts,
                    targetLanguage: targetLanguage,
                    apiKey: key
                )
            } else {
                translatedLines = await translateWithGoogle(lines: texts, targetLanguage: targetLanguage)
            }
        }

        let merged = document.lines.enumerated().map { idx, line -> LyricsLine in
            var copy = line
            if idx < translatedLines.count {
                copy.translated = translatedLines[idx]
            }
            return copy
        }

        return LyricsDocument(
            sourceProvider: document.sourceProvider,
            lines: merged,
            isSynced: document.isSynced,
            isWordTimed: document.isWordTimed,
            hasDuet: document.hasDuet,
            hasBackgroundVocals: document.hasBackgroundVocals,
            isSyllableSplit: document.isSyllableSplit,
            script: document.script
        )
    }

    private func translateWithGoogle(lines: [String], targetLanguage: String) async -> [String] {
        let joined = lines.joined(separator: "\n")
        var comps = URLComponents(string: "https://translate.googleapis.com/translate_a/single")!
        comps.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: "auto"),
            URLQueryItem(name: "tl", value: targetLanguage),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "q", value: joined),
        ]
        guard let url = comps.url,
              let (data, resp) = try? await session.data(from: url),
              let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let root = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let segments = root.first as? [[Any]] else {
            return []
        }
        let full = segments.compactMap { $0.first as? String }.joined()
        return full.components(separatedBy: "\n")
    }

    private func translateWithOpenRouter(lines: [String], targetLanguage: String, apiKey: String) async -> [String] {
        guard let url = URL(string: "https://openrouter.ai/api/v1/chat/completions") else { return [] }
        let numbered = lines.enumerated().map { "\($0.offset + 1)| \($0.element)" }.joined(separator: "\n")
        let payload: [String: Any] = [
            "model": "mistralai/mistral-small-latest",
            "messages": [
                ["role": "system", "content": "Translate each numbered lyric line into \(targetLanguage). Preserve line count and output ONLY translated lines separated by newlines."],
                ["role": "user", "content": numbered],
            ],
        ]
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        guard let (data, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let content = (choices.first?["message"] as? [String: Any])?["content"] as? String else {
            return []
        }
        return content
            .components(separatedBy: "\n")
            .map { $0.replacingOccurrences(of: #"^\d+\|\s*"#, with: "", options: .regularExpression) }
    }
}

// MARK: - Vocal-Activity Audio AutoSync

public enum LyricsAutoSync {
    /// Estimates lyric offset (ms) in `[-5000, +5000]` by correlating lyric line onsets with PCM RMS peaks.
    public static func estimateOffsetMs(
        monoPCM: [Float],
        sampleRate: Double,
        lyrics: LyricsDocument
    ) -> Int {
        guard !monoPCM.isEmpty, sampleRate > 0, lyrics.isSynced, lyrics.lines.count >= 3 else {
            return 0
        }

        let frameStepSamples = max(1, Int(sampleRate * 0.05)) // 50ms windows
        var envelope: [Float] = []
        var idx = 0
        while idx + frameStepSamples <= monoPCM.count {
            var sumSq: Float = 0
            for i in idx..<(idx + frameStepSamples) {
                let s = monoPCM[i]
                sumSq += s * s
            }
            envelope.append(sqrtf(sumSq / Float(frameStepSamples)))
            idx += frameStepSamples
        }
        guard !envelope.isEmpty else { return 0 }

        var bestOffsetMs = 0
        var bestScore: Float = -.greatestFiniteMagnitude

        for candidateOffset in stride(from: -5000, through: 5000, by: 100) {
            var score: Float = 0
            for line in lyrics.lines {
                let shiftedMs = line.startMs + candidateOffset
                let bin = shiftedMs / 50
                if bin >= 1 && bin < envelope.count {
                    // Reward lyric onset aligning with positive vocal energy rise.
                    score += envelope[bin] - 0.5 * envelope[bin - 1]
                }
            }
            if score > bestScore {
                bestScore = score
                bestOffsetMs = candidateOffset
            }
        }
        return bestOffsetMs
    }
}
