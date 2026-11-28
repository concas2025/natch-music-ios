import Foundation

// MARK: - Context & Request Bodies

public struct InnerTubeContext: Codable, Sendable, Equatable {
    public struct Client: Codable, Sendable, Equatable {
        public let clientName: String
        public let clientVersion: String
        public let clientScreen: String?
        public let platform: String?
        public let osName: String?
        public let osVersion: String?
        public let deviceMake: String?
        public let deviceModel: String?
        public let androidSdkVersion: String?
        public let gl: String
        public let hl: String
        public let visitorData: String?
        public let utcOffsetMinutes: Int?
    }

    public struct ThirdParty: Codable, Sendable, Equatable {
        public let embedUrl: String
    }

    public struct Request: Codable, Sendable, Equatable {
        public let internalExperimentFlags: [String]
        public let useSsl: Bool

        public init(internalExperimentFlags: [String] = [], useSsl: Bool = true) {
            self.internalExperimentFlags = internalExperimentFlags
            self.useSsl = useSsl
        }
    }

    public struct User: Codable, Sendable, Equatable {
        public let lockedSafetyMode: Bool
        public let onBehalfOfUser: String?

        public init(lockedSafetyMode: Bool = false, onBehalfOfUser: String? = nil) {
            self.lockedSafetyMode = lockedSafetyMode
            self.onBehalfOfUser = onBehalfOfUser
        }
    }

    public let client: Client
    public let thirdParty: ThirdParty?
    public let request: Request
    public let user: User

    public init(
        client: Client,
        thirdParty: ThirdParty? = nil,
        request: Request = Request(),
        user: User = User()
    ) {
        self.client = client
        self.thirdParty = thirdParty
        self.request = request
        self.user = user
    }
}

public struct PlayerBody: Codable, Sendable, Equatable {
    public struct PlaybackContext: Codable, Sendable, Equatable {
        public struct ContentPlaybackContext: Codable, Sendable, Equatable {
            public let signatureTimestamp: Int
            public let html5Preference: String

            public init(signatureTimestamp: Int, html5Preference: String = "HTML5_PREF_WANTS") {
                self.signatureTimestamp = signatureTimestamp
                self.html5Preference = html5Preference
            }
        }

        public let contentPlaybackContext: ContentPlaybackContext

        public init(contentPlaybackContext: ContentPlaybackContext) {
            self.contentPlaybackContext = contentPlaybackContext
        }
    }

    public struct ServiceIntegrityDimensions: Codable, Sendable, Equatable {
        public let poToken: String

        public init(poToken: String) {
            self.poToken = poToken
        }
    }

    public let context: InnerTubeContext
    public let videoId: String
    public let playlistId: String?
    public let playbackContext: PlaybackContext?
    public let serviceIntegrityDimensions: ServiceIntegrityDimensions?
    public let contentCheckOk: Bool
    public let racyCheckOk: Bool

    public init(
        context: InnerTubeContext,
        videoId: String,
        playlistId: String? = nil,
        playbackContext: PlaybackContext? = nil,
        serviceIntegrityDimensions: ServiceIntegrityDimensions? = nil,
        contentCheckOk: Bool = true,
        racyCheckOk: Bool = true
    ) {
        self.context = context
        self.videoId = videoId
        self.playlistId = playlistId
        self.playbackContext = playbackContext
        self.serviceIntegrityDimensions = serviceIntegrityDimensions
        self.contentCheckOk = contentCheckOk
        self.racyCheckOk = racyCheckOk
    }
}

public struct VisitorIdBody: Codable, Sendable, Equatable {
    public let context: InnerTubeContext
}

public struct SearchBody: Codable, Sendable, Equatable {
    public let context: InnerTubeContext
    public let query: String?
    public let params: String?
}

public struct BrowseBody: Codable, Sendable, Equatable {
    public let context: InnerTubeContext
    public let browseId: String?
    public let params: String?
    public let continuation: String?
}

public struct NextBody: Codable, Sendable, Equatable {
    public let context: InnerTubeContext
    public let videoId: String?
    public let playlistId: String?
    public let playlistSetVideoId: String?
    public let index: Int?
    public let params: String?
    public let continuation: String?
}

// MARK: - Flexible & Lossy JSON Decoding Helpers

private enum FlexJSON {
    static func decodeInt<K: CodingKey>(_ c: KeyedDecodingContainer<K>, forKey key: K) -> Int? {
        if let val = try? c.decodeIfPresent(Int.self, forKey: key) {
            return val
        }
        if let dbl = try? c.decodeIfPresent(Double.self, forKey: key) {
            return Int(dbl)
        }
        if let str = try? c.decodeIfPresent(String.self, forKey: key) {
            return Int(str.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    static func decodeInt64<K: CodingKey>(_ c: KeyedDecodingContainer<K>, forKey key: K) -> Int64? {
        if let val = try? c.decodeIfPresent(Int64.self, forKey: key) {
            return val
        }
        if let val = try? c.decodeIfPresent(Int.self, forKey: key) {
            return Int64(val)
        }
        if let str = try? c.decodeIfPresent(String.self, forKey: key) {
            return Int64(str.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    static func decodeDouble<K: CodingKey>(_ c: KeyedDecodingContainer<K>, forKey key: K) -> Double? {
        if let val = try? c.decodeIfPresent(Double.self, forKey: key) {
            return val
        }
        if let val = try? c.decodeIfPresent(Int.self, forKey: key) {
            return Double(val)
        }
        if let str = try? c.decodeIfPresent(String.self, forKey: key) {
            return Double(str.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    static func decodeString<K: CodingKey>(_ c: KeyedDecodingContainer<K>, forKey key: K) -> String? {
        if let val = try? c.decodeIfPresent(String.self, forKey: key) {
            return val
        }
        if let val = try? c.decodeIfPresent(Int64.self, forKey: key) {
            return String(val)
        }
        if let val = try? c.decodeIfPresent(Double.self, forKey: key) {
            return String(val)
        }
        return nil
    }

    static func decodeLossyArray<K: CodingKey, Element: Decodable>(
        _ c: KeyedDecodingContainer<K>,
        forKey key: K
    ) -> [Element]? {
        guard c.contains(key) else { return nil }
        return (try? c.decodeIfPresent(LossyDecodableArray<Element>.self, forKey: key))?.elements
    }
}

private struct LossyDecodableArray<Element: Decodable>: Decodable {
    let elements: [Element]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var decoded: [Element] = []
        while !container.isAtEnd {
            if (try? container.decodeNil()) == true {
                continue
            }
            if let item = try? container.decode(Element.self) {
                decoded.append(item)
            } else {
                _ = try? container.decode(SkipJSONValue.self)
            }
        }
        self.elements = decoded
    }
}

private enum SkipJSONValue: Decodable {
    case ignored

    init(from decoder: Decoder) throws {
        _ = try? decoder.singleValueContainer()
        self = .ignored
    }
}

// MARK: - Responses

public struct ResponseContext: Codable, Sendable, Equatable {
    public let visitorData: String?
}

public struct VisitorIdResponse: Codable, Sendable, Equatable {
    public let responseContext: ResponseContext?
}

public struct ThumbnailItem: Codable, Sendable, Equatable {
    public let url: String
    public let width: Int?
    public let height: Int?

    public init(url: String, width: Int? = nil, height: Int? = nil) {
        self.url = url
        self.width = width
        self.height = height
    }

    private enum CodingKeys: String, CodingKey {
        case url, width, height
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url = (try? c.decodeIfPresent(String.self, forKey: .url)) ?? ""
        width = FlexJSON.decodeInt(c, forKey: .width)
        height = FlexJSON.decodeInt(c, forKey: .height)
    }
}

public struct Thumbnails: Codable, Sendable, Equatable {
    public let thumbnails: [ThumbnailItem]

    public init(thumbnails: [ThumbnailItem] = []) {
        self.thumbnails = thumbnails
    }

    private enum CodingKeys: String, CodingKey {
        case thumbnails
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        thumbnails = FlexJSON.decodeLossyArray(c, forKey: .thumbnails) ?? []
    }
}

public struct PlayerResponse: Codable, Sendable, Equatable {
    public struct PlayabilityStatus: Codable, Sendable, Equatable {
        public let status: String
        public let reason: String?

        public init(status: String, reason: String? = nil) {
            self.status = status
            self.reason = reason
        }

        private enum CodingKeys: String, CodingKey {
            case status, reason
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            status = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? "UNKNOWN"
            reason = try? c.decodeIfPresent(String.self, forKey: .reason)
        }
    }

    public struct PlayerConfig: Codable, Sendable, Equatable {
        public struct AudioConfig: Codable, Sendable, Equatable {
            public let loudnessDb: Double?
            public let perceptualLoudnessDb: Double?

            public init(loudnessDb: Double? = nil, perceptualLoudnessDb: Double? = nil) {
                self.loudnessDb = loudnessDb
                self.perceptualLoudnessDb = perceptualLoudnessDb
            }

            private enum CodingKeys: String, CodingKey {
                case loudnessDb, perceptualLoudnessDb
            }

            public init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                loudnessDb = FlexJSON.decodeDouble(c, forKey: .loudnessDb)
                perceptualLoudnessDb = FlexJSON.decodeDouble(c, forKey: .perceptualLoudnessDb)
            }
        }

        public let audioConfig: AudioConfig?
    }

    public struct StreamingData: Codable, Sendable, Equatable {
        public struct Format: Codable, Sendable, Equatable {
            public struct ByteRange: Codable, Sendable, Equatable {
                public let start: String
                public let end: String

                public init(start: String, end: String) {
                    self.start = start
                    self.end = end
                }

                private enum CodingKeys: String, CodingKey {
                    case start, end
                }

                public init(from decoder: Decoder) throws {
                    let c = try decoder.container(keyedBy: CodingKeys.self)
                    start = FlexJSON.decodeString(c, forKey: .start) ?? "0"
                    end = FlexJSON.decodeString(c, forKey: .end) ?? "0"
                }
            }

            public struct AudioTrack: Codable, Sendable, Equatable {
                public let displayName: String?
                public let id: String?
                public let isAutoDubbed: Bool?
            }

            public let itag: Int
            public let url: String?
            public let mimeType: String
            public let bitrate: Int
            public let width: Int?
            public let height: Int?
            public let contentLength: Int64?
            public let quality: String?
            public let fps: Int?
            public let qualityLabel: String?
            public let averageBitrate: Int?
            public let audioQuality: String?
            public let approxDurationMs: String?
            public let audioSampleRate: Int?
            public let audioChannels: Int?
            public let loudnessDb: Double?
            public let lastModified: Int64?
            public let signatureCipher: String?
            public let cipher: String?
            public let audioTrack: AudioTrack?
            public let initRange: ByteRange?
            public let indexRange: ByteRange?

            public var isAudio: Bool { width == nil }
            public var isOriginal: Bool { audioTrack?.isAutoDubbed != true }

            public init(
                itag: Int,
                url: String? = nil,
                mimeType: String,
                bitrate: Int,
                width: Int? = nil,
                height: Int? = nil,
                contentLength: Int64? = nil,
                quality: String? = nil,
                fps: Int? = nil,
                qualityLabel: String? = nil,
                averageBitrate: Int? = nil,
                audioQuality: String? = nil,
                approxDurationMs: String? = nil,
                audioSampleRate: Int? = nil,
                audioChannels: Int? = nil,
                loudnessDb: Double? = nil,
                lastModified: Int64? = nil,
                signatureCipher: String? = nil,
                cipher: String? = nil,
                audioTrack: AudioTrack? = nil,
                initRange: ByteRange? = nil,
                indexRange: ByteRange? = nil
            ) {
                self.itag = itag
                self.url = url
                self.mimeType = mimeType
                self.bitrate = bitrate
                self.width = width
                self.height = height
                self.contentLength = contentLength
                self.quality = quality
                self.fps = fps
                self.qualityLabel = qualityLabel
                self.averageBitrate = averageBitrate
                self.audioQuality = audioQuality
                self.approxDurationMs = approxDurationMs
                self.audioSampleRate = audioSampleRate
                self.audioChannels = audioChannels
                self.loudnessDb = loudnessDb
                self.lastModified = lastModified
                self.signatureCipher = signatureCipher
                self.cipher = cipher
                self.audioTrack = audioTrack
                self.initRange = initRange
                self.indexRange = indexRange
            }

            private enum CodingKeys: String, CodingKey {
                case itag, url, mimeType, bitrate, width, height, contentLength, quality, fps
                case qualityLabel, averageBitrate, audioQuality, approxDurationMs, audioSampleRate
                case audioChannels, loudnessDb, lastModified, signatureCipher, cipher, audioTrack
                case initRange, indexRange
            }

            public init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                guard let decodedItag = FlexJSON.decodeInt(c, forKey: .itag) else {
                    throw DecodingError.dataCorruptedError(
                        forKey: .itag,
                        in: c,
                        debugDescription: "Missing or invalid itag"
                    )
                }
                itag = decodedItag
                url = try? c.decodeIfPresent(String.self, forKey: .url)
                mimeType = (try? c.decodeIfPresent(String.self, forKey: .mimeType)) ?? ""
                bitrate = FlexJSON.decodeInt(c, forKey: .bitrate) ?? 0
                width = FlexJSON.decodeInt(c, forKey: .width)
                height = FlexJSON.decodeInt(c, forKey: .height)
                contentLength = FlexJSON.decodeInt64(c, forKey: .contentLength)
                quality = try? c.decodeIfPresent(String.self, forKey: .quality)
                fps = FlexJSON.decodeInt(c, forKey: .fps)
                qualityLabel = try? c.decodeIfPresent(String.self, forKey: .qualityLabel)
                averageBitrate = FlexJSON.decodeInt(c, forKey: .averageBitrate)
                audioQuality = try? c.decodeIfPresent(String.self, forKey: .audioQuality)
                approxDurationMs = FlexJSON.decodeString(c, forKey: .approxDurationMs)
                audioSampleRate = FlexJSON.decodeInt(c, forKey: .audioSampleRate)
                audioChannels = FlexJSON.decodeInt(c, forKey: .audioChannels)
                loudnessDb = FlexJSON.decodeDouble(c, forKey: .loudnessDb)
                lastModified = FlexJSON.decodeInt64(c, forKey: .lastModified)
                signatureCipher = try? c.decodeIfPresent(String.self, forKey: .signatureCipher)
                cipher = try? c.decodeIfPresent(String.self, forKey: .cipher)
                audioTrack = try? c.decodeIfPresent(AudioTrack.self, forKey: .audioTrack)
                initRange = try? c.decodeIfPresent(ByteRange.self, forKey: .initRange)
                indexRange = try? c.decodeIfPresent(ByteRange.self, forKey: .indexRange)
            }
        }

        public let formats: [Format]?
        public let adaptiveFormats: [Format]
        public let expiresInSeconds: Int

        public init(
            formats: [Format]? = nil,
            adaptiveFormats: [Format] = [],
            expiresInSeconds: Int = 21_540
        ) {
            self.formats = formats
            self.adaptiveFormats = adaptiveFormats
            self.expiresInSeconds = expiresInSeconds
        }

        private enum CodingKeys: String, CodingKey {
            case formats, adaptiveFormats, expiresInSeconds
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            formats = FlexJSON.decodeLossyArray(c, forKey: .formats)
            adaptiveFormats = FlexJSON.decodeLossyArray(c, forKey: .adaptiveFormats) ?? []
            // YouTube routinely sends `expiresInSeconds` as a JSON string ("21540") or integer.
            expiresInSeconds = FlexJSON.decodeInt(c, forKey: .expiresInSeconds) ?? 21_540
        }
    }

    public struct VideoDetails: Codable, Sendable, Equatable {
        public let videoId: String
        public let title: String?
        public let author: String?
        public let channelId: String
        public let lengthSeconds: String
        public let musicVideoType: String?
        public let viewCount: String?
        public let thumbnail: Thumbnails?

        public init(
            videoId: String,
            title: String? = nil,
            author: String? = nil,
            channelId: String = "",
            lengthSeconds: String = "0",
            musicVideoType: String? = nil,
            viewCount: String? = nil,
            thumbnail: Thumbnails? = nil
        ) {
            self.videoId = videoId
            self.title = title
            self.author = author
            self.channelId = channelId
            self.lengthSeconds = lengthSeconds
            self.musicVideoType = musicVideoType
            self.viewCount = viewCount
            self.thumbnail = thumbnail
        }

        private enum CodingKeys: String, CodingKey {
            case videoId, title, author, channelId, lengthSeconds, musicVideoType, viewCount, thumbnail
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            videoId = (try? c.decodeIfPresent(String.self, forKey: .videoId)) ?? ""
            title = try? c.decodeIfPresent(String.self, forKey: .title)
            author = try? c.decodeIfPresent(String.self, forKey: .author)
            channelId = (try? c.decodeIfPresent(String.self, forKey: .channelId)) ?? ""
            lengthSeconds = FlexJSON.decodeString(c, forKey: .lengthSeconds) ?? "0"
            musicVideoType = try? c.decodeIfPresent(String.self, forKey: .musicVideoType)
            viewCount = FlexJSON.decodeString(c, forKey: .viewCount)
            thumbnail = try? c.decodeIfPresent(Thumbnails.self, forKey: .thumbnail)
        }
    }

    public struct Captions: Codable, Sendable, Equatable {
        public struct PlayerCaptionsTracklistRenderer: Codable, Sendable, Equatable {
            public let captionTracks: [CaptionTrack]?
        }

        public struct CaptionTrack: Codable, Sendable, Equatable {
            public let baseUrl: String
            public let languageCode: String?
            public let kind: String?

            public var isAutoGenerated: Bool { kind == "asr" }

            public init(baseUrl: String, languageCode: String? = nil, kind: String? = nil) {
                self.baseUrl = baseUrl
                self.languageCode = languageCode
                self.kind = kind
            }

            private enum CodingKeys: String, CodingKey {
                case baseUrl, languageCode, kind
            }

            public init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                baseUrl = (try? c.decodeIfPresent(String.self, forKey: .baseUrl)) ?? ""
                languageCode = try? c.decodeIfPresent(String.self, forKey: .languageCode)
                kind = try? c.decodeIfPresent(String.self, forKey: .kind)
            }
        }

        public let playerCaptionsTracklistRenderer: PlayerCaptionsTracklistRenderer?
    }

    public let responseContext: ResponseContext?
    public let playabilityStatus: PlayabilityStatus
    public let playerConfig: PlayerConfig?
    public let streamingData: StreamingData?
    public let videoDetails: VideoDetails?
    public let captions: Captions?
}
