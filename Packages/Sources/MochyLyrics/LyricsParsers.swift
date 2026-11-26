import Foundation

// MARK: - LRC & Enhanced LRC Parser

public enum LRCParser {
    private static let lineTagRegex = try! NSRegularExpression(
        pattern: #"\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]"#
    )
    private static let wordTagRegex = try! NSRegularExpression(
        pattern: #"<(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?>([^<\n]*)"#
    )

    public static func parse(_ raw: String, provider: String) -> LyricsDocument? {
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
        let rawLines = normalized.components(separatedBy: "\n")

        var parsedLines: [LyricsLine] = []
        var anySynced = false
        var anyWordTimed = false

        for rawLine in rawLines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            let nsRange = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
            let matches = lineTagRegex.matches(in: trimmed, range: nsRange)

            if matches.isEmpty {
                // Skip metadata headers like [ar:...], [ti:...]
                if trimmed.hasPrefix("[") && trimmed.contains(":") && trimmed.hasSuffix("]") {
                    continue
                }
                parsedLines.append(LyricsLine(startMs: 0, text: trimmed))
                continue
            }

            anySynced = true
            let lastMatchEnd = matches.last!.range.location + matches.last!.range.length
            let startIndex = trimmed.index(trimmed.startIndex, offsetBy: lastMatchEnd)
            let body = String(trimmed[startIndex...]).trimmingCharacters(in: .whitespaces)
            if body.isEmpty { continue }

            for m in matches {
                let startMs = parseTimestampMs(in: trimmed, match: m)
                let (words, cleanText) = parseWordTags(body: body, lineStartMs: startMs)
                if !words.isEmpty { anyWordTimed = true }
                parsedLines.append(
                    LyricsLine(
                        startMs: startMs,
                        endMs: words.last?.endMs,
                        text: cleanText,
                        words: words
                    )
                )
            }
        }

        guard !parsedLines.isEmpty else { return nil }
        if anySynced {
            parsedLines.sort { $0.startMs < $1.startMs }
        }
        let fullText = parsedLines.map(\.text).joined(separator: " ")
        return LyricsDocument(
            sourceProvider: provider,
            lines: parsedLines,
            isSynced: anySynced,
            isWordTimed: anyWordTimed,
            script: ScriptDetector.detect(fullText)
        )
    }

    private static func parseWordTags(body: String, lineStartMs: Int) -> ([LyricsWord], String) {
        let range = NSRange(body.startIndex..<body.endIndex, in: body)
        let matches = wordTagRegex.matches(in: body, range: range)
        guard !matches.isEmpty else { return ([], body) }

        var words: [LyricsWord] = []
        var clean = ""
        for (idx, m) in matches.enumerated() {
            let startMs = parseTimestampMs(in: body, match: m)
            guard let textRange = Range(m.range(at: 4), in: body) else { continue }
            let token = String(body[textRange])
            let trimmedToken = token.trimmingCharacters(in: .whitespaces)
            let nextStart: Int
            if idx + 1 < matches.count {
                nextStart = parseTimestampMs(in: body, match: matches[idx + 1])
            } else {
                nextStart = max(startMs + 400, lineStartMs + 2500)
            }
            if !trimmedToken.isEmpty {
                words.append(LyricsWord(startMs: startMs, endMs: nextStart, text: trimmedToken))
            }
            clean += token
        }
        return (words, clean.trimmingCharacters(in: .whitespaces))
    }

    private static func parseTimestampMs(in text: String, match: NSTextCheckingResult) -> Int {
        func intGroup(_ idx: Int) -> Int {
            guard idx < match.numberOfRanges,
                  let r = Range(match.range(at: idx), in: text) else { return 0 }
            return Int(text[r]) ?? 0
        }
        let mins = intGroup(1)
        let secs = intGroup(2)
        var fracMs = 0
        if match.numberOfRanges > 3, let r = Range(match.range(at: 3), in: text) {
            let rawFrac = String(text[r])
            let val = Int(rawFrac) ?? 0
            switch rawFrac.count {
            case 1: fracMs = val * 100
            case 2: fracMs = val * 10
            default: fracMs = val
            }
        }
        return mins * 60_000 + secs * 1_000 + fracMs
    }
}

// MARK: - KRC Word-Timed Parser

public enum KRCParser {
    private static let lineRegex = try! NSRegularExpression(pattern: #"^\[(\d+),(\d+)\](.+)$"#)
    private static let wordRegex = try! NSRegularExpression(pattern: #"<(\d+),(\d+),\d+>([^<]*)"#)

    public static func parse(_ raw: String, provider: String = "KuGou") -> LyricsDocument? {
        var lines: [LyricsLine] = []
        var anyWord = false

        for row in raw.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let nsRange = NSRange(row.startIndex..<row.endIndex, in: row)
            guard let m = lineRegex.firstMatch(in: row, range: nsRange),
                  let sR = Range(m.range(at: 1), in: row),
                  let dR = Range(m.range(at: 2), in: row),
                  let bR = Range(m.range(at: 3), in: row),
                  let startMs = Int(row[sR]),
                  let durMs = Int(row[dR]) else {
                continue
            }
            let body = String(row[bR])
            let bRange = NSRange(body.startIndex..<body.endIndex, in: body)
            let wMatches = wordRegex.matches(in: body, range: bRange)

            var words: [LyricsWord] = []
            var lineText = ""
            for wm in wMatches {
                guard let wsR = Range(wm.range(at: 1), in: body),
                      let wdR = Range(wm.range(at: 2), in: body),
                      let wtR = Range(wm.range(at: 3), in: body),
                      let wOffset = Int(body[wsR]),
                      let wDur = Int(body[wdR]) else { continue }
                let token = String(body[wtR])
                lineText += token
                let trimmed = token.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    anyWord = true
                    words.append(LyricsWord(startMs: startMs + wOffset, endMs: startMs + wOffset + wDur, text: trimmed))
                }
            }
            if !lineText.trimmingCharacters(in: .whitespaces).isEmpty {
                lines.append(
                    LyricsLine(
                        startMs: startMs,
                        endMs: startMs + durMs,
                        text: lineText.trimmingCharacters(in: .whitespaces),
                        words: words
                    )
                )
            }
        }

        guard !lines.isEmpty else { return nil }
        return LyricsDocument(
            sourceProvider: provider,
            lines: lines,
            isSynced: true,
            isWordTimed: anyWord,
            script: ScriptDetector.detect(lines.map(\.text).joined(separator: " "))
        )
    }
}

// MARK: - Apple Music TTML Parser (Duet Agents & Background Vocals)

public final class TTMLParser: NSObject, XMLParserDelegate {
    private var lines: [LyricsLine] = []
    private var inParagraph = false
    private var pBeginMs = 0
    private var pEndMs: Int?
    private var pAgent: DuetAgent?
    private var pText = ""
    private var pWords: [LyricsWord] = []

    private var inSpan = false
    private var spanBeginMs = 0
    private var spanEndMs = 0
    private var spanBackground = false
    private var spanBuffer = ""

    private var hasDuet = false
    private var hasBackground = false
    private var anyWord = false

    public static func parse(_ xmlString: String, provider: String = "BetterLyrics") -> LyricsDocument? {
        guard let data = xmlString.data(using: .utf8) else { return nil }
        let parserDelegate = TTMLParser()
        let xml = XMLParser(data: data)
        xml.delegate = parserDelegate
        guard xml.parse(), !parserDelegate.lines.isEmpty else { return nil }

        let fullText = parserDelegate.lines.map(\.text).joined(separator: " ")
        return LyricsDocument(
            sourceProvider: provider,
            lines: parserDelegate.lines,
            isSynced: true,
            isWordTimed: parserDelegate.anyWord,
            hasDuet: parserDelegate.hasDuet,
            hasBackgroundVocals: parserDelegate.hasBackground,
            script: ScriptDetector.detect(fullText)
        )
    }

    public func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        let local = elementName.components(separatedBy: ":").last ?? elementName
        if local == "p" {
            inParagraph = true
            pBeginMs = Self.parseTime(attributeDict["begin"]) ?? 0
            pEndMs = Self.parseTime(attributeDict["end"])
            let agentRaw = attributeDict["ttm:agent"] ?? attributeDict["agent"] ?? ""
            if agentRaw == "v2" {
                pAgent = .v2
                hasDuet = true
            } else if agentRaw == "v1" {
                pAgent = .v1
            } else {
                pAgent = nil
            }
            pText = ""
            pWords = []
        } else if local == "span", inParagraph {
            let role = attributeDict["ttm:role"] ?? attributeDict["role"] ?? ""
            inSpan = true
            spanBackground = (role == "x-bg")
            if spanBackground { hasBackground = true }
            spanBeginMs = Self.parseTime(attributeDict["begin"]) ?? pBeginMs
            spanEndMs = Self.parseTime(attributeDict["end"]) ?? (spanBeginMs + 300)
            spanBuffer = ""
        }
    }

    public func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inSpan {
            spanBuffer += string
        } else if inParagraph {
            pText += string
        }
    }

    public func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let local = elementName.components(separatedBy: ":").last ?? elementName
        if local == "span", inSpan {
            let wordText = spanBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !wordText.isEmpty {
                anyWord = true
                pWords.append(
                    LyricsWord(
                        startMs: spanBeginMs,
                        endMs: spanEndMs,
                        text: wordText,
                        isBackground: spanBackground
                    )
                )
                pText += (pText.isEmpty ? "" : " ") + wordText
            }
            inSpan = false
            spanBuffer = ""
        } else if local == "p", inParagraph {
            let clean = pText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty {
                lines.append(
                    LyricsLine(
                        startMs: pBeginMs,
                        endMs: pEndMs,
                        text: clean,
                        words: pWords,
                        agent: pAgent,
                        isBackground: pWords.allSatisfy(\.isBackground) && !pWords.isEmpty
                    )
                )
            }
            inParagraph = false
        }
    }

    private static func parseTime(_ raw: String?) -> Int? {
        guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else {
            return nil
        }
        if s.hasSuffix("s") {
            s.removeLast()
            return Double(s).map { Int($0 * 1000.0) }
        }
        let parts = s.split(separator: ":")
        switch parts.count {
        case 1:
            return Double(parts[0]).map { Int($0 * 1000.0) }
        case 2:
            guard let m = Double(parts[0]), let sec = Double(parts[1]) else { return nil }
            return Int((m * 60.0 + sec) * 1000.0)
        case 3:
            guard let h = Double(parts[0]), let m = Double(parts[1]), let sec = Double(parts[2]) else { return nil }
            return Int((h * 3600.0 + m * 60.0 + sec) * 1000.0)
        default:
            return nil
        }
    }
}
