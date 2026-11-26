import Foundation
import MochyCore
import MochyInnerTube

public protocol LyricsProvider: Sendable {
    var name: String { get }
    var isChineseProvider: Bool { get }
    func fetch(query: LyricsQuery) async -> LyricsDocument?
}

public extension LyricsProvider {
    var isChineseProvider: Bool { false }
}

// MARK: - Priority 0: Local Sidecar Files (.ttml / .lrc)

public struct LocalSidecarLyricsProvider: LyricsProvider {
    public let name = "LocalFile"

    public init() {}

    public func fetch(query: LyricsQuery) async -> LyricsDocument? {
        guard let audioURL = query.localFileURL else { return nil }
        let base = audioURL.deletingPathExtension()
        let ttmlURL = base.appendingPathExtension("ttml")
        if let raw = try? String(contentsOf: ttmlURL, encoding: .utf8),
           let doc = TTMLParser.parse(raw, provider: name) {
            return doc
        }
        let lrcURL = base.appendingPathExtension("lrc")
        if let raw = try? String(contentsOf: lrcURL, encoding: .utf8),
           let doc = LRCParser.parse(raw, provider: name) {
            return doc
        }
        return nil
    }
}

// MARK: - BetterLyrics (Apple Music TTML)

public struct BetterLyricsProvider: LyricsProvider {
    public let name = "BetterLyrics"
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetch(query: LyricsQuery) async -> LyricsDocument? {
        var comps = URLComponents(string: "https://lyrics-api.boidu.dev/getLyrics")!
        comps.queryItems = [
            URLQueryItem(name: "s", value: TrackMatcher.core(query.title)),
            URLQueryItem(name: "a", value: query.artist),
            URLQueryItem(name: "d", value: String(max(0, query.durationSeconds))),
        ]
        if let album = query.album, !album.isEmpty {
            comps.queryItems?.append(URLQueryItem(name: "al", value: album))
        }
        guard let url = comps.url,
              let json = await LyricsHTTP.getJSON(url: url, session: session),
              let ttml = json["ttml"] as? String else {
            return nil
        }
        return TTMLParser.parse(ttml, provider: name)
    }
}

// MARK: - Unison

public struct UnisonProvider: LyricsProvider {
    public let name = "Unison"
    private let session: URLSession

    public init(session: URLSession = .shared) { self.session = session }

    public func fetch(query: LyricsQuery) async -> LyricsDocument? {
        var comps = URLComponents(string: "https://unison.betterlyrics.org/api/lyrics")!
        comps.queryItems = [
            URLQueryItem(name: "title", value: TrackMatcher.core(query.title)),
            URLQueryItem(name: "artist", value: query.artist),
            URLQueryItem(name: "duration", value: String(query.durationSeconds)),
        ]
        guard let url = comps.url,
              let json = await LyricsHTTP.getJSON(url: url, session: session) else {
            return nil
        }
        if let ttml = json["ttml"] as? String, let doc = TTMLParser.parse(ttml, provider: name) {
            return doc
        }
        if let lrc = json["lrc"] as? String {
            return LRCParser.parse(lrc, provider: name)
        }
        return nil
    }
}

// MARK: - YouLyPlus / LyricsPlus (Mirrors verified in Mochy YouLyPlus.kt)

public struct YouLyPlusProvider: LyricsProvider {
    public let name = "YouLyPlus"
    private static let servers = [
        "https://lyricsplus.prjktla.my.id",
        "https://lyricsplus.binimum.org",
    ]
    private let session: URLSession

    public init(session: URLSession = .shared) { self.session = session }

    public func fetch(query: LyricsQuery) async -> LyricsDocument? {
        for base in Self.servers {
            var comps = URLComponents(string: "\(base)/v2/lyrics/get")!
            comps.queryItems = [
                URLQueryItem(name: "title", value: TrackMatcher.core(query.title)),
                URLQueryItem(name: "artist", value: query.artist),
                URLQueryItem(name: "duration", value: String(query.durationSeconds)),
                URLQueryItem(name: "source", value: "apple,lyricsplus,musixmatch,spotify"),
            ]
            if let album = query.album { comps.queryItems?.append(URLQueryItem(name: "album", value: album)) }
            guard let url = comps.url,
                  let json = await LyricsHTTP.getJSON(url: url, session: session),
                  let rawLyrics = json["lyrics"] as? [[String: Any]], !rawLyrics.isEmpty else {
                continue
            }

            var lines: [LyricsLine] = []
            var anyWord = false
            for row in rawLyrics {
                let text = (row["text"] as? String) ?? ""
                let start = (row["time"] as? Int) ?? 0
                let dur = (row["duration"] as? Int) ?? 3000
                let syllabus = (row["syllabus"] as? [[String: Any]]) ?? []
                var words: [LyricsWord] = []
                for syl in syllabus {
                    guard let wText = syl["text"] as? String else { continue }
                    let wStart = (syl["time"] as? Int) ?? start
                    let wDur = (syl["duration"] as? Int) ?? 300
                    anyWord = true
                    words.append(LyricsWord(startMs: wStart, endMs: wStart + wDur, text: wText))
                }
                if !text.isEmpty {
                    lines.append(LyricsLine(startMs: start, endMs: start + dur, text: text, words: words))
                }
            }
            if !lines.isEmpty {
                return LyricsDocument(
                    sourceProvider: name,
                    lines: lines,
                    isSynced: true,
                    isWordTimed: anyWord,
                    script: ScriptDetector.detect(lines.map(\.text).joined(separator: " "))
                )
            }
        }
        return nil
    }
}

// MARK: - LrcRed

public struct LrcRedProvider: LyricsProvider {
    public let name = "LrcRed"
    private let session: URLSession

    public init(session: URLSession = .shared) { self.session = session }

    public func fetch(query: LyricsQuery) async -> LyricsDocument? {
        var comps = URLComponents(string: "https://lrc.red/api/lyrics")!
        comps.queryItems = [
            URLQueryItem(name: "title", value: TrackMatcher.core(query.title)),
            URLQueryItem(name: "artist", value: query.artist),
        ]
        guard let url = comps.url,
              let json = await LyricsHTTP.getJSON(url: url, session: session),
              let lrc = json["lyrics"] as? String else {
            return nil
        }
        return LRCParser.parse(lrc, provider: name)
    }
}

// MARK: - SimpMusic Lyrics

public struct SimpMusicProvider: LyricsProvider {
    public let name = "SimpMusic"
    private let session: URLSession

    public init(session: URLSession = .shared) { self.session = session }

    public func fetch(query: LyricsQuery) async -> LyricsDocument? {
        guard let url = URL(string: "https://api-lyrics.simpmusic.org/v1/\(query.videoId)"),
              let json = await LyricsHTTP.getJSON(url: url, session: session),
              let list = json["data"] as? [[String: Any]],
              let first = list.first else {
            return nil
        }
        if let synced = first["syncedLyrics"] as? String, let doc = LRCParser.parse(synced, provider: name) {
            return doc
        }
        if let rich = first["richSyncLyrics"] as? String, let doc = LRCParser.parse(rich, provider: name) {
            return doc
        }
        if let plain = first["plainLyric"] as? String {
            return LRCParser.parse(plain, provider: name)
        }
        return nil
    }
}

// MARK: - LrcLib

public struct LrcLibProvider: LyricsProvider {
    public let name = "LrcLib"
    private let session: URLSession

    public init(session: URLSession = .shared) { self.session = session }

    public func fetch(query: LyricsQuery) async -> LyricsDocument? {
        var comps = URLComponents(string: "https://lrclib.net/api/get")!
        comps.queryItems = [
            URLQueryItem(name: "track_name", value: TrackMatcher.core(query.title)),
            URLQueryItem(name: "artist_name", value: query.artist),
        ]
        if let album = query.album, !album.isEmpty {
            comps.queryItems?.append(URLQueryItem(name: "album_name", value: album))
        }
        if query.durationSeconds > 0 {
            comps.queryItems?.append(URLQueryItem(name: "duration", value: String(query.durationSeconds)))
        }
        if let url = comps.url, let json = await LyricsHTTP.getJSON(url: url, session: session) {
            if let synced = json["syncedLyrics"] as? String, let doc = LRCParser.parse(synced, provider: name) {
                return doc
            }
            if let plain = json["plainLyrics"] as? String, let doc = LRCParser.parse(plain, provider: name) {
                return doc
            }
        }
        return nil
    }
}

// MARK: - Deezer / NetEase / QQMusic / KuGou / YouTube Captions

public struct NetEaseLyricsProvider: LyricsProvider {
    public let name = "NetEase"
    public let isChineseProvider = true
    private let session: URLSession

    public init(session: URLSession = .shared) { self.session = session }

    public func fetch(query: LyricsQuery) async -> LyricsDocument? {
        var searchComps = URLComponents(string: "https://music.163.com/api/search/get")!
        searchComps.queryItems = [
            URLQueryItem(name: "s", value: "\(TrackMatcher.core(query.title)) \(query.artist)"),
            URLQueryItem(name: "type", value: "1"),
            URLQueryItem(name: "limit", value: "5"),
        ]
        guard let sURL = searchComps.url,
              let sJson = await LyricsHTTP.getJSON(url: sURL, session: session),
              let songs = ((sJson["result"] as? [String: Any])?["songs"] as? [[String: Any]]),
              let firstId = songs.first?["id"] as? Int else {
            return nil
        }
        guard let lyricURL = URL(string: "https://music.163.com/api/song/lyric?id=\(firstId)&lv=1&kv=1&tv=-1"),
              let lJson = await LyricsHTTP.getJSON(url: lyricURL, session: session),
              let rawLrc = (lJson["lrc"] as? [String: Any])?["lyric"] as? String else {
            return nil
        }
        return LRCParser.parse(rawLrc, provider: name)
    }
}

public struct QQMusicLyricsProvider: LyricsProvider {
    public let name = "QQMusic"
    public let isChineseProvider = true
    public init() {}
    public func fetch(query: LyricsQuery) async -> LyricsDocument? { nil } // Gated by QQ musicu token payload; handled in pickBest priority list
}

public struct KuGouLyricsProvider: LyricsProvider {
    public let name = "KuGou"
    public let isChineseProvider = true
    private let session: URLSession

    public init(session: URLSession = .shared) { self.session = session }

    public func fetch(query: LyricsQuery) async -> LyricsDocument? {
        var searchComps = URLComponents(string: "https://lyrics.kugou.com/search")!
        searchComps.queryItems = [
            URLQueryItem(name: "ver", value: "1"),
            URLQueryItem(name: "man", value: "yes"),
            URLQueryItem(name: "client", value: "mobi"),
            URLQueryItem(name: "keyword", value: "\(TrackMatcher.core(query.title)) - \(query.artist)"),
            URLQueryItem(name: "duration", value: String(max(1, query.durationSeconds) * 1000)),
        ]
        guard let url = searchComps.url,
              let json = await LyricsHTTP.getJSON(url: url, session: session),
              let candidates = json["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let cid = first["id"],
              let accesskey = first["accesskey"] as? String else {
            return nil
        }
        var dlComps = URLComponents(string: "https://lyrics.kugou.com/download")!
        dlComps.queryItems = [
            URLQueryItem(name: "ver", value: "1"),
            URLQueryItem(name: "client", value: "pc"),
            URLQueryItem(name: "id", value: "\(cid)"),
            URLQueryItem(name: "accesskey", value: accesskey),
            URLQueryItem(name: "fmt", value: "lrc"),
            URLQueryItem(name: "charset", value: "utf8"),
        ]
        guard let dlURL = dlComps.url,
              let dlJson = await LyricsHTTP.getJSON(url: dlURL, session: session),
              let b64 = dlJson["content"] as? String,
              let decodedData = Data(base64Encoded: b64),
              let lrc = String(data: decodedData, encoding: .utf8) else {
            return nil
        }
        return LRCParser.parse(lrc, provider: name)
    }
}

public struct YouTubeCaptionsLyricsProvider: LyricsProvider {
    public let name = "YouTubeCaptions"
    private let innerTube: InnerTubeClient
    private let session: URLSession

    public init(innerTube: InnerTubeClient = InnerTubeClient(), session: URLSession = .shared) {
        self.innerTube = innerTube
        self.session = session
    }

    public func fetch(query: LyricsQuery) async -> LyricsDocument? {
        guard let response = try? await innerTube.player(client: .web, videoId: query.videoId),
              let tracks = response.captions?.playerCaptionsTracklistRenderer?.captionTracks,
              let track = tracks.first(where: { !$0.isAutoGenerated }) ?? tracks.first,
              let url = URL(string: "\(track.baseUrl)&fmt=srv3"),
              let (data, _) = try? await session.data(from: url),
              let xml = String(data: data, encoding: .utf8) else {
            return nil
        }
        return TTMLParser.parse(xml, provider: name)
    }
}

private enum LyricsHTTP {
    static let userAgent = "Mochy (+https://github.com/realidkroo/Mochy-Music)"

    static func getJSON(url: URL, session: URLSession) async -> [String: Any]? {
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return obj
    }
}
