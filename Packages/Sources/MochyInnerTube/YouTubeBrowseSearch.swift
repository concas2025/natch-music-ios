import Foundation

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

public struct YTVideoStreamOption: Sendable, Equatable, Identifiable {
    public let itag: Int
    public let qualityLabel: String
    public let width: Int
    public let height: Int
    public let url: URL
    public let mimeType: String
    public var id: Int { itag }
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

    public func browseHome(browseId: String = "FEmusic_home") async throws -> [YTHomeSection] {
        let client = YouTubeClient.metadataClient
        let visitor = await resolvedVisitorId(for: client)
        let body = BrowseBody(
            context: client.toContext(locale: locale, visitorData: visitor, dataSyncId: nil),
            browseId: browseId,
            params: nil,
            continuation: nil
        )
        let data = try await rawPost(endpoint: "browse", client: client, body: body)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        return InnerTubeParser.extractHomeSections(from: root)
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
    /// Resolves progressive/adaptive video streams (144p–2160p) for the `VIDEO` player style.
    public func resolveVideoStreams(videoId: String) async throws -> [YTVideoStreamOption] {
        for client in [YouTubeClient.visionOS, YouTubeClient.iPadOS, YouTubeClient.androidVR16148] {
            guard let response = try? await player(client: client, videoId: videoId),
                  response.playabilityStatus.status == "OK",
                  let streamingData = response.streamingData else {
                continue
            }
            let combined = (streamingData.formats ?? []) + streamingData.adaptiveFormats
            let videoFormats = combined.compactMap { fmt -> YTVideoStreamOption? in
                guard let height = fmt.height, let width = fmt.width,
                      let rawURL = fmt.url, let url = URL(string: rawURL),
                      fmt.mimeType.lowercased().contains("mp4") else {
                    return nil
                }
                return YTVideoStreamOption(
                    itag: fmt.itag,
                    qualityLabel: fmt.qualityLabel ?? "\(height)p",
                    width: width,
                    height: height,
                    url: url,
                    mimeType: fmt.mimeType
                )
            }
            if !videoFormats.isEmpty {
                return videoFormats.sorted { $0.height > $1.height }
            }
        }
        return []
    }

    private func player(client: YouTubeClient, videoId: String) async throws -> PlayerResponse {
        // Delegates internally to the actor's innerTube client via existing public player API.
        try await resolveRawPlayer(client: client, videoId: videoId)
    }
}

// MARK: - Recursive Renderer Parsers

public enum InnerTubeParser {
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
            let thumbs = (((panel["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]])?.last?["url"] as? String)
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
            let thumbs = ((((responsive["thumbnail"] as? [String: Any])?["musicThumbnailRenderer"] as? [String: Any])?["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]])?.last?["url"] as? String
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
            let thumbs = ((((twoRow["thumbnailRenderer"] as? [String: Any])?["musicThumbnailRenderer"] as? [String: Any])?["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]])?.last?["url"] as? String
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
