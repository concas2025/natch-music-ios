import Foundation
import MochyCore

// MARK: - High-level YouTube Music Catalog Models

public struct YTTrackItem: Sendable, Equatable, Identifiable, Codable {
    public let id: String
    public let title: String
    public let artists: [String]
    public let album: String?
    public let durationSeconds: Int?
    public let thumbnailURL: String?
    public let explicit: Bool
    public let isVideo: Bool

    public init(
        id: String,
        title: String,
        artists: [String],
        album: String? = nil,
        durationSeconds: Int? = nil,
        thumbnailURL: String? = nil,
        explicit: Bool = false,
        isVideo: Bool = false
    ) {
        self.id = id
        self.title = title
        self.artists = artists
        self.album = album
        self.durationSeconds = durationSeconds
        self.thumbnailURL = thumbnailURL
        self.explicit = explicit
        self.isVideo = isVideo
    }

    public var artistDisplay: String {
        artists.isEmpty ? "Unknown Artist" : artists.joined(separator: ", ")
    }
}

public struct YTHomeSection: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let items: [YTTrackItem]

    public init(id: String, title: String, items: [YTTrackItem]) {
        self.id = id
        self.title = title
        self.items = items
    }
}

public struct YTPlaylistSummary: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let thumbnailURL: String?
    public let trackCountText: String?

    public init(id: String, title: String, thumbnailURL: String? = nil, trackCountText: String? = nil) {
        self.id = id
        self.title = title
        self.thumbnailURL = thumbnailURL
        self.trackCountText = trackCountText
    }
}

public struct YTBrowseCollection: Sendable, Equatable {
    public let title: String
    public let subtitle: String?
    public let thumbnailURL: String?
    public let tracks: [YTTrackItem]

    public init(title: String, subtitle: String? = nil, thumbnailURL: String? = nil, tracks: [YTTrackItem]) {
        self.title = title
        self.subtitle = subtitle
        self.thumbnailURL = thumbnailURL
        self.tracks = tracks
    }
}

public struct YTVideoStreamOption: Sendable, Equatable, Identifiable {
    public let itag: Int
    public let qualityLabel: String
    public let width: Int
    public let height: Int
    public let url: URL
    public let mimeType: String
    public let headers: [String: String]
    public let isProgressive: Bool
    public var id: Int { itag }

    public init(
        itag: Int,
        qualityLabel: String,
        width: Int,
        height: Int,
        url: URL,
        mimeType: String,
        headers: [String: String] = [:],
        isProgressive: Bool = false
    ) {
        self.itag = itag
        self.qualityLabel = qualityLabel
        self.width = width
        self.height = height
        self.url = url
        self.mimeType = mimeType
        self.headers = headers
        self.isProgressive = isProgressive
    }
}

// MARK: - Defensive YouTube Music JSON Navigation & Queries

extension InnerTubeClient {
    public func searchTracks(query: String, params: String? = "EgWKAQIIAWoKEAMQBBAJEAoQBQ%3D%3D") async throws -> [YTTrackItem] {
        let client = YouTubeClient.metadataClient
        let visitor = await resolvedVisitorId(for: client)
        let body = SearchBody(
            context: client.toContext(locale: locale, visitorData: visitor, dataSyncId: nil),
            query: query,
            params: params
        )
        let data = try await rawPost(endpoint: "search", client: client, body: body)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        return InnerTubeParser.extractTracks(from: root)
    }

    public func searchSuggestions(query: String) async throws -> [String] {
        let client = YouTubeClient.metadataClient
        let visitor = await resolvedVisitorId(for: client)
        struct SuggestBody: Encodable {
            let context: InnerTubeContext
            let input: String
        }
        let body = SuggestBody(
            context: client.toContext(locale: locale, visitorData: visitor, dataSyncId: nil),
            input: query
        )
        let data = try await rawPost(endpoint: "music/get_search_suggestions", client: client, body: body)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        return InnerTubeParser.extractSuggestions(from: root)
    }

    public func browseHome(browseId: String = "FEmusic_home", setLogin: Bool = false) async throws -> [YTHomeSection] {
        let client = YouTubeClient.metadataClient
        let visitor = await resolvedVisitorId(for: client)
        let syncId = setLogin ? dataSyncId : nil
        let body = BrowseBody(
            context: client.toContext(locale: locale, visitorData: visitor, dataSyncId: syncId),
            browseId: browseId,
            params: nil,
            continuation: nil
        )
        let data = try await rawPost(endpoint: "browse", client: client, body: body, setLogin: setLogin)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let sections = InnerTubeParser.extractHomeSections(from: root)
        if !sections.isEmpty {
            return sections
        }
        let flat = InnerTubeParser.extractTracks(from: root)
        return flat.isEmpty ? [] : [YTHomeSection(id: browseId, title: "Library", items: flat)]
    }

    public func browsePlaylist(playlistId: String, setLogin: Bool = false) async throws -> YTBrowseCollection {
        let normalizedId = (playlistId.hasPrefix("VL") || playlistId.hasPrefix("FE") || playlistId.hasPrefix("MPRE") || playlistId.hasPrefix("UC"))
            ? playlistId
            : "VL\(playlistId)"
        let client = YouTubeClient.metadataClient
        let visitor = await resolvedVisitorId(for: client)
        let syncId = setLogin ? dataSyncId : nil
        let body = BrowseBody(
            context: client.toContext(locale: locale, visitorData: visitor, dataSyncId: syncId),
            browseId: normalizedId,
            params: nil,
            continuation: nil
        )
        let data = try await rawPost(endpoint: "browse", client: client, body: body, setLogin: setLogin)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return YTBrowseCollection(title: "YouTube Playlist", tracks: [])
        }
        let meta = InnerTubeParser.extractHeaderMetadata(from: root)
        let tracks = InnerTubeParser.extractTracks(from: root)
        return YTBrowseCollection(
            title: meta.title ?? "YouTube Playlist",
            subtitle: meta.subtitle,
            thumbnailURL: meta.thumbnailURL ?? tracks.first?.thumbnailURL,
            tracks: tracks
        )
    }

    public func browseLibraryPlaylists() async throws -> [YTPlaylistSummary] {
        let client = YouTubeClient.metadataClient
        let visitor = await resolvedVisitorId(for: client)
        let body = BrowseBody(
            context: client.toContext(locale: locale, visitorData: visitor, dataSyncId: dataSyncId),
            browseId: "FEmusic_liked_playlists",
            params: nil,
            continuation: nil
        )
        let data = try await rawPost(endpoint: "browse", client: client, body: body, setLogin: true)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        return InnerTubeParser.extractPlaylists(from: root)
    }

    public func nextQueue(videoId: String, playlistId: String? = nil) async throws -> [YTTrackItem] {
        let client = YouTubeClient.metadataClient
        let visitor = await resolvedVisitorId(for: client)
        let body = NextBody(
            context: client.toContext(locale: locale, visitorData: visitor, dataSyncId: nil),
            videoId: videoId,
            playlistId: playlistId ?? "RDAMVM\(videoId)",
            playlistSetVideoId: nil,
            index: nil,
            params: nil,
            continuation: nil
        )
        let data = try await rawPost(endpoint: "next", client: client, body: body)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        return InnerTubeParser.extractTracks(from: root)
    }
}

extension YTPlayerResolver {
    /// Resolves progressive & adaptive MP4 video streams (360p–2160p) with EJS deobfuscation and required headers.
    public func resolveVideoStreams(videoId: String) async throws -> [YTVideoStreamOption] {
        let cookie = await innerTube.cookie
        for client in [YouTubeClient.visionOS, YouTubeClient.iPadOS, YouTubeClient.mobile, YouTubeClient.webRemix] {
            guard let response = try? await resolveRawPlayer(client: client, videoId: videoId),
                  response.playabilityStatus.status == "OK",
                  let streamingData = response.streamingData else {
                continue
            }
            let headers = Self.streamHeaders(for: client, cookie: client.loginSupported ? cookie : nil)
            var options: [YTVideoStreamOption] = []

            for fmt in streamingData.formats ?? [] {
                guard let height = fmt.height, let width = fmt.width,
                      fmt.mimeType.lowercased().contains("mp4"),
                      let resolvedStr = try? await resolveFormatURL(format: fmt, client: client),
                      let url = URL(string: resolvedStr) else {
                    continue
                }
                options.append(
                    YTVideoStreamOption(
                        itag: fmt.itag,
                        qualityLabel: fmt.qualityLabel ?? "\(height)p",
                        width: width,
                        height: height,
                        url: url,
                        mimeType: fmt.mimeType,
                        headers: headers,
                        isProgressive: true
                    )
                )
            }

            for fmt in streamingData.adaptiveFormats {
                guard let height = fmt.height, let width = fmt.width,
                      fmt.mimeType.lowercased().contains("video/mp4"),
                      let resolvedStr = try? await resolveFormatURL(format: fmt, client: client),
                      let url = URL(string: resolvedStr) else {
                    continue
                }
                options.append(
                    YTVideoStreamOption(
                        itag: fmt.itag,
                        qualityLabel: fmt.qualityLabel ?? "\(height)p",
                        width: width,
                        height: height,
                        url: url,
                        mimeType: fmt.mimeType,
                        headers: headers,
                        isProgressive: false
                    )
                )
            }

            if !options.isEmpty {
                // Prefer progressive muxed MP4 first for guaranteed iOS playback, then higher resolution MP4.
                return options.sorted { lhs, rhs in
                    if lhs.isProgressive != rhs.isProgressive { return lhs.isProgressive }
                    return lhs.height > rhs.height
                }
            }
        }
        return []
    }
}

// MARK: - Recursive Renderer Parsers

public enum InnerTubeParser {
    public static func extractHeaderMetadata(from root: Any) -> (title: String?, subtitle: String?, thumbnailURL: String?) {
        var title: String?
        var subtitle: String?
        var thumb: String?
        walkDictionaries(root) { dict in
            let header = (dict["musicResponsiveHeaderRenderer"] as? [String: Any])
                ?? (dict["musicDetailHeaderRenderer"] as? [String: Any])
                ?? (dict["musicImmersiveHeaderRenderer"] as? [String: Any])
            guard let header else { return }
            if title == nil {
                title = (header["title"] as? [String: Any]).flatMap { runsText($0) }
            }
            if subtitle == nil {
                subtitle = (header["subtitle"] as? [String: Any]).flatMap { runsText($0) }
            }
            if thumb == nil {
                let rawThumb = ((((header["thumbnail"] as? [String: Any])?["musicThumbnailRenderer"] as? [String: Any])?["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]])?.last?["url"] as? String
                thumb = ThumbnailURLUpgrader.upgrade(rawThumb)
            }
        }
        return (title, subtitle, thumb)
    }

    public static func extractPlaylists(from root: Any) -> [YTPlaylistSummary] {
        var out: [YTPlaylistSummary] = []
        var seen = Set<String>()
        walkDictionaries(root) { dict in
            guard let twoRow = dict["musicTwoRowItemRenderer"] as? [String: Any],
                  let nav = twoRow["navigationEndpoint"] as? [String: Any],
                  let browse = nav["browseEndpoint"] as? [String: Any],
                  let browseId = browse["browseId"] as? String,
                  browseId.hasPrefix("VL") || browseId.hasPrefix("PL") else {
                return
            }
            guard seen.insert(browseId).inserted else { return }
            let title = (twoRow["title"] as? [String: Any]).flatMap { runsText($0) } ?? "Playlist"
            let sub = (twoRow["subtitle"] as? [String: Any]).flatMap { runsText($0) }
            let rawThumb = ((((twoRow["thumbnailRenderer"] as? [String: Any])?["musicThumbnailRenderer"] as? [String: Any])?["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]])?.last?["url"] as? String
            let thumb = ThumbnailURLUpgrader.upgrade(rawThumb)
            out.append(YTPlaylistSummary(id: browseId, title: title, thumbnailURL: thumb, trackCountText: sub))
        }
        return out
    }

    public static func extractSuggestions(from root: Any) -> [String] {
        var results: [String] = []
        walkDictionaries(root) { dict in
            if let renderer = dict["searchSuggestionRenderer"] as? [String: Any],
               let suggestion = renderer["suggestion"] as? [String: Any],
               let runs = suggestion["runs"] as? [[String: Any]] {
                let text = runs.compactMap { $0["text"] as? String }.joined()
                if !text.isEmpty && !results.contains(text) {
                    results.append(text)
                }
            }
        }
        return results
    }

    public static func extractHomeSections(from root: Any) -> [YTHomeSection] {
        var sections: [YTHomeSection] = []
        walkDictionaries(root) { dict in
            guard let carousel = dict["musicCarouselShelfRenderer"] as? [String: Any] else { return }
            let headerTitle = (((carousel["header"] as? [String: Any])?["musicCarouselShelfBasicHeaderRenderer"] as? [String: Any])?["title"] as? [String: Any])
                .flatMap { runsText($0) } ?? "Recommended"
            let contents = carousel["contents"] as? [[String: Any]] ?? []
            let tracks = contents.compactMap { parseTrack($0) }
            if !tracks.isEmpty {
                sections.append(YTHomeSection(id: "\(headerTitle)-\(sections.count)", title: headerTitle, items: tracks))
            }
        }
        return sections
    }

    public static func extractTracks(from root: Any) -> [YTTrackItem] {
        var items: [YTTrackItem] = []
        var seenIds = Set<String>()
        walkDictionaries(root) { dict in
            if let track = parseTrack(dict), seenIds.insert(track.id).inserted {
                items.append(track)
            }
        }
        return items
    }

    private static func parseTrack(_ dict: [String: Any]) -> YTTrackItem? {
        if let panel = dict["playlistPanelVideoRenderer"] as? [String: Any],
           let videoId = panel["videoId"] as? String {
            let title = (panel["title"] as? [String: Any]).flatMap { runsText($0) } ?? "Unknown"
            let artistText = (panel["shortBylineText"] as? [String: Any]).flatMap { runsText($0) } ?? ""
            let artists = splitArtists(artistText)
            let lengthStr = (panel["lengthText"] as? [String: Any]).flatMap { runsText($0) }
            let thumbs = ThumbnailURLUpgrader.upgrade((((panel["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]])?.last?["url"] as? String))
            return YTTrackItem(
                id: videoId,
                title: title,
                artists: artists,
                durationSeconds: parseDurationSeconds(lengthStr),
                thumbnailURL: thumbs
            )
        }

        if let responsive = dict["musicResponsiveListItemRenderer"] as? [String: Any] {
            let videoId = (((responsive["playlistItemData"] as? [String: Any])?["videoId"] as? String)
                ?? ((((responsive["overlay"] as? [String: Any])?["musicItemThumbnailOverlayRenderer"] as? [String: Any])?["content"] as? [String: Any])?["musicPlayButtonRenderer"] as? [String: Any])
                .flatMap { (($0["playNavigationEndpoint"] as? [String: Any])?["watchEndpoint"] as? [String: Any])?["videoId"] as? String })
            guard let videoId, !videoId.isEmpty else { return nil }

            let cols = responsive["flexColumns"] as? [[String: Any]] ?? []
            let title = colText(cols, index: 0) ?? "Unknown"
            let subtitle = colText(cols, index: 1) ?? ""
            let parts = subtitle.components(separatedBy: " • ")
            let artists = splitArtists(parts.first ?? "")
            let duration = parts.last.flatMap { parseDurationSeconds($0) }
                ?? (responsive["fixedColumns"] as? [[String: Any]])
                    .flatMap { fixed -> Int? in
                        guard let first = fixed.first?["musicResponsiveListItemFixedColumnRenderer"] as? [String: Any],
                              let txt = first["text"] as? [String: Any] else { return nil }
                        return parseDurationSeconds(runsText(txt))
                    }
            let thumbs = ThumbnailURLUpgrader.upgrade(((((responsive["thumbnail"] as? [String: Any])?["musicThumbnailRenderer"] as? [String: Any])?["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]])?.last?["url"] as? String)
            return YTTrackItem(
                id: videoId,
                title: title,
                artists: artists,
                durationSeconds: duration,
                thumbnailURL: thumbs
            )
        }

        if let twoRow = dict["musicTwoRowItemRenderer"] as? [String: Any],
           let watch = ((twoRow["navigationEndpoint"] as? [String: Any])?["watchEndpoint"] as? [String: Any]),
           let videoId = watch["videoId"] as? String {
            let title = (twoRow["title"] as? [String: Any]).flatMap { runsText($0) } ?? "Unknown"
            let subtitle = (twoRow["subtitle"] as? [String: Any]).flatMap { runsText($0) } ?? ""
            let thumbs = ThumbnailURLUpgrader.upgrade(((((twoRow["thumbnailRenderer"] as? [String: Any])?["musicThumbnailRenderer"] as? [String: Any])?["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]])?.last?["url"] as? String)
            return YTTrackItem(
                id: videoId,
                title: title,
                artists: splitArtists(subtitle),
                thumbnailURL: thumbs
            )
        }
        return nil
    }

    private static func colText(_ cols: [[String: Any]], index: Int) -> String? {
        guard index < cols.count,
              let renderer = cols[index]["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any],
              let text = renderer["text"] as? [String: Any] else { return nil }
        return runsText(text)
    }

    private static func runsText(_ obj: [String: Any]) -> String? {
        if let simple = obj["simpleText"] as? String { return simple }
        guard let runs = obj["runs"] as? [[String: Any]] else { return nil }
        let joined = runs.compactMap { $0["text"] as? String }.joined()
        return joined.isEmpty ? nil : joined
    }

    private static func splitArtists(_ raw: String) -> [String] {
        raw.components(separatedBy: CharacterSet(charactersIn: ",&"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "•" }
    }

    private static func parseDurationSeconds(_ text: String?) -> Int? {
        guard let text else { return nil }
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":").compactMap { Int($0) }
        switch parts.count {
        case 2: return parts[0] * 60 + parts[1]
        case 3: return parts[0] * 3600 + parts[1] * 60 + parts[2]
        default: return nil
        }
    }

    private static func walkDictionaries(_ value: Any, visit: ([String: Any]) -> Void) {
        if let dict = value as? [String: Any] {
            visit(dict)
            for child in dict.values {
                walkDictionaries(child, visit: visit)
            }
        } else if let array = value as? [Any] {
            for child in array {
                walkDictionaries(child, visit: visit)
            }
        }
    }
}
