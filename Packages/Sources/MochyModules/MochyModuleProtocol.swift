import Foundation
import MochyCore

public struct ModuleTrack: Sendable, Equatable {
    public let id: String
    public let title: String
    public let artist: String
    public let durationSeconds: Int?
    public let isrc: String?
    public let localFileURL: URL?

    public init(
        id: String,
        title: String,
        artist: String,
        durationSeconds: Int? = nil,
        isrc: String? = nil,
        localFileURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.durationSeconds = durationSeconds
        self.isrc = isrc
        self.localFileURL = localFileURL
    }
}

public enum StreamFormat: String, Codable, Sendable, Equatable {
    case progressive
    case hls
    case dash
}

public struct ModuleStream: Sendable, Equatable {
    public let url: URL
    public let headers: [String: String]
    public let format: StreamFormat
    public let codec: String
    public let sampleRate: Int?
    public let bitDepth: Int?
    public let bitrate: Int?
    public let sourceId: String
    public let sourceLabel: String
    public let qualityBadge: String
    public let isDRM: Bool
    public let loudnessDb: Double?

    public init(
        url: URL,
        headers: [String: String] = [:],
        format: StreamFormat = .progressive,
        codec: String,
        sampleRate: Int? = nil,
        bitDepth: Int? = nil,
        bitrate: Int? = nil,
        sourceId: String,
        sourceLabel: String,
        qualityBadge: String,
        isDRM: Bool = false,
        loudnessDb: Double? = nil
    ) {
        self.url = url
        self.headers = headers
        self.format = format
        self.codec = codec
        self.sampleRate = sampleRate
        self.bitDepth = bitDepth
        self.bitrate = bitrate
        self.sourceId = sourceId
        self.sourceLabel = sourceLabel
        self.qualityBadge = qualityBadge
        self.isDRM = isDRM
        self.loudnessDb = loudnessDb
    }
}

public protocol MochyStreamModule: Sendable {
    var id: String { get }
    var displayName: String { get }
    var supportsDownload: Bool { get }
    func resolve(track: ModuleTrack, quality: AudioQuality) async throws -> ModuleStream?
}

/// Security & sanitization boundary ported from Mochy's `ModuleUrlGuard` & `ModuleSanitizer`.
public enum ModuleUrlGuard {
    public static let maxManifestBytes = 256 * 1024

    public static func isAllowedPublicURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host?.lowercased(), !host.isEmpty else {
            return false
        }

        if host == "localhost" || host == "::1" || host.hasSuffix(".local") {
            return false
        }

        if let ipv4 = parseIPv4(host) {
            let a = ipv4[0], b = ipv4[1]
            if a == 10 || a == 127 || a == 0 { return false }
            if a == 169 && b == 254 { return false }
            if a == 172 && (16...31).contains(b) { return false }
            if a == 192 && b == 168 { return false }
            if a == 100 && (64...127).contains(b) { return false }
        }

        if host.hasPrefix("fe80:") || host.hasPrefix("fc") || host.hasPrefix("fd") {
            return false
        }
        return true
    }

    public static func sanitizeHeaders(_ headers: [String: String], allowSameOriginCookies: Bool = false) -> [String: String] {
        headers.filter { key, _ in
            let lower = key.lowercased()
            if !allowSameOriginCookies && (lower == "cookie" || lower == "authorization") {
                return false
            }
            return true
        }
    }

    private static func parseIPv4(_ host: String) -> [UInt8]? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var bytes: [UInt8] = []
        for p in parts {
            guard let v = UInt8(p) else { return nil }
            bytes.append(v)
        }
        return bytes
    }
}

public struct ModuleSkinManifest: Codable, Sendable, Equatable {
    public struct Block: Codable, Sendable, Equatable, Identifiable {
        public let id: String
        public let kind: String // "cover", "title", "artist", "seekbar", "transport", "lyrics", "visualizer"
        public let height: Double?
        public let cornerRadius: Double?
        public let alignment: String?
    }

    public let id: String
    public let name: String
    public let author: String?
    public let backgroundHex: [String]
    public let accentHex: String?
    public let lookOverrides: [String: String]?
    public let blocks: [Block]

    public var sanitizedLookOverrides: [LookSettingKey: String] {
        var filtered: [LookSettingKey: String] = [:]
        for (k, v) in lookOverrides ?? [:] {
            if let key = LookSettingKey(rawValue: k) {
                filtered[key] = v
            }
        }
        return filtered
    }

    public static let defaultSkin = ModuleSkinManifest(
        id: "mochy.default.skin",
        name: "Editorial Glass",
        author: "Mochy",
        backgroundHex: ["#111018", "#07070A"],
        accentHex: "#E84570",
        lookOverrides: ["blurQuality": "HIGH"],
        blocks: [
            Block(id: "b1", kind: "cover", height: 290, cornerRadius: 20, alignment: "center"),
            Block(id: "b2", kind: "title", height: nil, cornerRadius: nil, alignment: "leading"),
            Block(id: "b3", kind: "visualizer", height: 48, cornerRadius: 8, alignment: "center"),
            Block(id: "b4", kind: "seekbar", height: 40, cornerRadius: nil, alignment: "center"),
            Block(id: "b5", kind: "transport", height: 72, cornerRadius: nil, alignment: "center"),
        ]
    )
}
