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
    public let subtitle: String?
    public let year: String?
    public let browseId: String?

    public init(
        id: String,
        title: String,
        artists: [String],
        album: String? = nil,
        durationSeconds: Int? = nil,
        thumbnailURL: String? = nil,
        explicit: Bool = false,
        isVideo: Bool = false,
        subtitle: String? = nil,
        year: String? = nil,
        browseId: String? = nil
    ) {
        self.id = id
        self.title = title
        self.artists = artists
        self.album = album
        self.durationSeconds = durationSeconds
        self.thumbnailURL = thumbnailURL
        self.explicit = explicit
        self.isVideo = isVideo
        self.subtitle = subtitle
        self.year = year
        self.browseId = browseId
    }

    public var artistDisplay: String {
        artists.isEmpty ? "Unknown Artist" : artists.joined(separator: ", ")
    }
}

public enum YTHomeSectionKind: String, Sendable, Equatable, Codable {
    case standard
    case columns3
    case artistSimilar
    case moreLikeArtist
    case musicVideos
    case becauseGenre
    case trySomethingNew
    case liveShows
    case newFromArtists
    case speedDial
}

public struct YTHomeSection: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let avatarURL: String?
    public let kind: YTHomeSectionKind
    public let items: [YTTrackItem]

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        avatarURL: String? = nil,
        kind: YTHomeSectionKind = .standard,
        items: [YTTrackItem]
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.avatarURL = avatarURL
        self.kind = kind
        self.items = items
    }
}

public struct YTArtistSummary: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let thumbnailURL: String?
    public let subscribers: String?

    public init(id: String, name: String, thumbnailURL: String? = nil, subscribers: String? = nil) {
        self.id = id
        self.name = name
        self.thumbnailURL = thumbnailURL
        self.subscribers = subscribers
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

    public func browseHome(
        browseId: String = "FEmusic_home",
        setLogin: Bool = false,
        maxPages: Int = 2
    ) async throws -> [YTHomeSection] {
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
        var sections = InnerTubeParser.extractHomeSections(from: root)
        var continuation = InnerTubeParser.extractContinuationToken(from: root)
        var page = 1

        while page < max(1, maxPages), let token = continuation, !token.isEmpty {
            let contBody = BrowseBody(
                context: client.toContext(locale: locale, visitorData: visitor, dataSyncId: syncId),
                browseId: nil,
                params: nil,
                continuation: token
            )
            guard let nextData = try? await rawPost(endpoint: "browse", client: client, body: contBody, setLogin: setLogin),
                  let nextRoot = try? JSONSerialization.jsonObject(with: nextData) as? [String: Any] else {
                break
            }
            let moreSections = InnerTubeParser.extractHomeSections(from: nextRoot)
            if moreSections.isEmpty { break }
            sections.append(contentsOf: moreSections)
            continuation = InnerTubeParser.extractContinuationToken(from: nextRoot)
            page += 1
        }

        if !sections.isEmpty {
            return sections
        }
        let flat = InnerTubeParser.extractTracks(from: root)
        return flat.isEmpty ? [] : [YTHomeSection(id: browseId, title: "Library", items: flat)]
    }

    public func browseChartsArtists() async throws -> (artists: [YTArtistSummary], playlists: [YTPlaylistSummary]) {
        let client = YouTubeClient.metadataClient
        let visitor = await resolvedVisitorId(for: client)
        let body = BrowseBody(
            context: client.toContext(locale: locale, visitorData: visitor, dataSyncId: nil),
            browseId: "FEmusic_charts",
            params: nil,
            continuation: nil
        )
        let data = try await rawPost(endpoint: "browse", client: client, body: body, setLogin: false)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ([], [])
        }
        return (InnerTubeParser.extractArtists(from: root), InnerTubeParser.extractPlaylists(from: root))
    }

    /// Builds a rich multi-shelf Home feed:
    /// - Signed in (Gmail): uses authenticated `FEmusic_home` (3 pages) + fills any missing visual shelves from library/charts.
    /// - Signed out (Guest): 100% localized (default VN) real YouTube Music home, charts, V-Pop/Indie/Rap, MV, Live Shows & New Releases.
    public func loadRichHomeFeed(
        isSignedIn: Bool,
        topLocalArtists: [String] = [],
        countryCode: String = "VN",
        languageCode: String = "vi"
    ) async -> [YTHomeSection] {
        updateLocale(countryCode: countryCode, languageCode: languageCode)
        let upperGL = countryCode.uppercased()

        async let homeTask: [YTHomeSection] = (try? await browseHome(
            browseId: "FEmusic_home",
            setLogin: isSignedIn,
            maxPages: isSignedIn ? 3 : 2
        )) ?? []
        async let chartsTask: (artists: [YTArtistSummary], playlists: [YTPlaylistSummary]) =
            (try? await browseChartsArtists()) ?? ([], [])

        let fetchedHome = await homeTask
        let charts = await chartsTask

        let mvPlaylistId: String? = {
            if upperGL == "VN" {
                return charts.playlists.first(where: { $0.title.localizedCaseInsensitiveContains("video") })?.id
                    ?? "VLPL4fGSI1pDJn57DkisEwlIpcs9FAt5yudJ"
            }
            return charts.playlists.first?.id
        }()

        let primaryArtist = topLocalArtists.first
            ?? charts.artists.first?.name
            ?? (upperGL == "VN" ? "Sơn Tùng M-TP" : "Trending")
        let primaryArtistAvatar = charts.artists.first(where: {
            $0.name.localizedCaseInsensitiveContains(primaryArtist) || primaryArtist.localizedCaseInsensitiveContains($0.name)
        })?.thumbnailURL ?? charts.artists.first?.thumbnailURL

        let secondArtist = topLocalArtists.dropFirst().first
            ?? charts.artists.dropFirst().first?.name
            ?? (upperGL == "VN" ? "Vũ." : primaryArtist)

        let genreFocus = upperGL == "VN" ? "V-Pop & Indie" : "Pop & Indie"
        let newDiscovery = upperGL == "VN" ? "Rap & Chill Việt" : "Electronic & Alt"

        async let mvTask = fetchMusicVideos(playlistId: mvPlaylistId, upperGL: upperGL)

        async let similarArtistTracksTask: [YTTrackItem] =
            (try? await searchTracks(query: "\(primaryArtist) songs")) ?? []
        async let moreLikeTracksTask: [YTTrackItem] =
            (try? await searchTracks(query: "\(secondArtist) hits")) ?? []
        async let genreTracksTask: [YTTrackItem] =
            (try? await searchTracks(query: upperGL == "VN" ? "nhạc trẻ vpop hay nhất hiện nay" : "top pop indie hits")) ?? []
        async let discoveryTracksTask: [YTTrackItem] =
            (try? await searchTracks(query: upperGL == "VN" ? "indie rap việt chill mới" : "indie chill new music")) ?? []
        async let liveShowsTask: [YTTrackItem] =
            (try? await searchTracks(query: upperGL == "VN" ? "live session concert việt nam" : "live concert acoustic session", params: "EgWKAQIQAWoKEAMQBBAJEAoQBQ%3D%3D")) ?? []
        async let newReleasesTask: [YTTrackItem] =
            (try? await searchTracks(query: upperGL == "VN" ? "nhạc mới phát hành vpop 2025 2026" : "new music releases 2025 2026")) ?? []

        let (mvTracks, similarTracks, moreLikeTracks, genreTracks, discoveryTracks, liveTracks, newTracks) = await (
            mvTask,
            similarArtistTracksTask,
            moreLikeTracksTask,
            genreTracksTask,
            discoveryTracksTask,
            liveShowsTask,
            newReleasesTask
        )

        var result: [YTHomeSection] = []
        var usedKinds = Set<YTHomeSectionKind>()
        var seenTitles = Set<String>()

        for section in fetchedHome {
            let key = section.title.lowercased()
            if seenTitles.insert(key).inserted {
                result.append(section)
                usedKinds.insert(section.kind)
            }
        }

        if !usedKinds.contains(.artistSimilar) && !similarTracks.isEmpty {
            let artistThumb = primaryArtistAvatar ?? similarTracks.first?.thumbnailURL
            result.append(YTHomeSection(
                id: "artist-similar-\(primaryArtist)",
                title: "Artist List",
                subtitle: "Similar to \(primaryArtist)",
                avatarURL: artistThumb,
                kind: .artistSimilar,
                items: Array(similarTracks.prefix(12))
            ))
        }

        if !usedKinds.contains(.moreLikeArtist) && !moreLikeTracks.isEmpty {
            let secondAvatar = charts.artists.dropFirst().first?.thumbnailURL ?? moreLikeTracks.first?.thumbnailURL
            result.append(YTHomeSection(
                id: "more-like-\(secondArtist)",
                title: secondArtist,
                subtitle: "MORE LIKE",
                avatarURL: secondAvatar,
                kind: .moreLikeArtist,
                items: Array(moreLikeTracks.prefix(12))
            ))
        }

        if !usedKinds.contains(.musicVideos) && !mvTracks.isEmpty {
            result.append(YTHomeSection(
                id: "music-videos-\(upperGL)",
                title: "Music Videos for You",
                subtitle: upperGL == "VN" ? "Top V-Pop & Trending MV" : "Trending Video Mix",
                kind: .musicVideos,
                items: Array(mvTracks.prefix(12))
            ))
        }

        if !usedKinds.contains(.becauseGenre) && !genreTracks.isEmpty {
            result.append(YTHomeSection(
                id: "because-genre-\(upperGL)",
                title: genreFocus,
                subtitle: "BECAUSE YOU LISTEN TO",
                kind: .becauseGenre,
                items: Array(genreTracks.prefix(12))
            ))
        }

        if !usedKinds.contains(.trySomethingNew) && !discoveryTracks.isEmpty {
            result.append(YTHomeSection(
                id: "try-new-\(upperGL)",
                title: newDiscovery,
                subtitle: "TRY SOMETHING NEW",
                kind: .trySomethingNew,
                items: Array(discoveryTracks.prefix(12))
            ))
        }

        if !usedKinds.contains(.liveShows) && !liveTracks.isEmpty {
            result.append(YTHomeSection(
                id: "live-shows-\(upperGL)",
                title: "Live Shows",
                subtitle: "Acoustic & Stage Performances",
                kind: .liveShows,
                items: Array(liveTracks.prefix(10))
            ))
        }

        if !usedKinds.contains(.newFromArtists) && !newTracks.isEmpty {
            result.append(YTHomeSection(
                id: "new-releases-\(upperGL)",
                title: "New from your artists",
                subtitle: upperGL == "VN" ? "Latest Releases" : "Fresh Drops",
                kind: .newFromArtists,
                items: Array(newTracks.prefix(12))
            ))
        }

        return result
    }

    private func fetchMusicVideos(playlistId: String?, upperGL: String) async -> [YTTrackItem] {
        if let playlistId,
           let col = try? await browsePlaylist(playlistId: playlistId, setLogin: false),
           !col.tracks.isEmpty {
            return col.tracks.map { item in
                YTTrackItem(
                    id: item.id,
                    title: item.title,
                    artists: item.artists,
                    album: item.album,
                    durationSeconds: item.durationSeconds,
                    thumbnailURL: item.thumbnailURL,
                    explicit: item.explicit,
                    isVideo: true,
                    subtitle: item.subtitle,
                    year: item.year,
                    browseId: item.browseId
                )
            }
        }
        let mvQuery = upperGL == "VN" ? "official music video vpop 2025" : "official music video 2025"
        return (try? await searchTracks(query: mvQuery, params: "EgWKAQIQAWoKEAMQBBAJEAoQBQ%3D%3D")) ?? []
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
                let sorted = options.sorted { lhs, rhs in
                    if lhs.isProgressive != rhs.isProgressive { return lhs.isProgressive }
                    return lhs.height > rhs.height
                }
                let probeCandidate = sorted.first(where: { $0.height <= 720 }) ?? sorted[0]
                let check = await validateAndMeasureStream(
                    url: probeCandidate.url,
                    client: client,
                    contentLength: Self.extractClenParam(from: probeCandidate.url),
                    cookie: client.loginSupported ? cookie : nil
                )
                guard check.isValid else { continue }

                if let healthyHost = check.validatedURL.host, healthyHost != probeCandidate.url.host {
                    return sorted.map { opt in
                        var comps = URLComponents(url: opt.url, resolvingAgainstBaseURL: false)
                        comps?.host = healthyHost
                        return YTVideoStreamOption(
                            itag: opt.itag,
                            qualityLabel: opt.qualityLabel,
                            width: opt.width,
                            height: opt.height,
                            url: comps?.url ?? opt.url,
                            mimeType: opt.mimeType,
                            headers: opt.headers,
                            isProgressive: opt.isProgressive
                        )
                    }
                }
                return sorted
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

    public static func extractContinuationToken(from root: Any) -> String? {
        var token: String?
        walkDictionaries(root) { dict in
            guard token == nil else { return }
            if let cont = dict["nextContinuationData"] as? [String: Any],
               let t = cont["continuation"] as? String,
               !t.isEmpty {
                token = t
            } else if let cmd = dict["continuationCommand"] as? [String: Any],
                      let t = cmd["token"] as? String,
                      !t.isEmpty {
                token = t
            }
        }
        return token
    }

    public static func extractArtists(from root: Any) -> [YTArtistSummary] {
        var out: [YTArtistSummary] = []
        var seen = Set<String>()
        walkDictionaries(root) { dict in
            if let responsive = dict["musicResponsiveListItemRenderer"] as? [String: Any],
               let nav = responsive["navigationEndpoint"] as? [String: Any],
               let browse = nav["browseEndpoint"] as? [String: Any],
               let browseId = browse["browseId"] as? String,
               browseId.hasPrefix("UC"),
               seen.insert(browseId).inserted {
                let cols = responsive["flexColumns"] as? [[String: Any]] ?? []
                let name = colText(cols, index: 0) ?? "Artist"
                let subs = colText(cols, index: 1)
                let rawThumb = ((((responsive["thumbnail"] as? [String: Any])?["musicThumbnailRenderer"] as? [String: Any])?["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]])?.last?["url"] as? String
                out.append(YTArtistSummary(id: browseId, name: name, thumbnailURL: ThumbnailURLUpgrader.upgrade(rawThumb), subscribers: subs))
            } else if let twoRow = dict["musicTwoRowItemRenderer"] as? [String: Any],
                      let nav = twoRow["navigationEndpoint"] as? [String: Any],
                      let browse = nav["browseEndpoint"] as? [String: Any],
                      let browseId = browse["browseId"] as? String,
                      browseId.hasPrefix("UC"),
                      seen.insert(browseId).inserted {
                let name = (twoRow["title"] as? [String: Any]).flatMap { runsText($0) } ?? "Artist"
                let subs = (twoRow["subtitle"] as? [String: Any]).flatMap { runsText($0) }
                let rawThumb = ((((twoRow["thumbnailRenderer"] as? [String: Any])?["musicThumbnailRenderer"] as? [String: Any])?["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]])?.last?["url"] as? String
                out.append(YTArtistSummary(id: browseId, name: name, thumbnailURL: ThumbnailURLUpgrader.upgrade(rawThumb), subscribers: subs))
            }
        }
        return out
    }

    public static func extractHomeSections(from root: Any) -> [YTHomeSection] {
        var sections: [YTHomeSection] = []
        walkDictionaries(root) { dict in
            guard let carousel = dict["musicCarouselShelfRenderer"] as? [String: Any] else { return }
            let header = (carousel["header"] as? [String: Any])?["musicCarouselShelfBasicHeaderRenderer"] as? [String: Any]
            let headerTitle = (header?["title"] as? [String: Any]).flatMap { runsText($0) } ?? "Recommended"
            let headerStrapline = (header?["strapline"] as? [String: Any]).flatMap { runsText($0) }
            let rawAvatar = ((((header?["thumbnail"] as? [String: Any])?["musicThumbnailRenderer"] as? [String: Any])?["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]])?.last?["url"] as? String
            let headerAvatar = ThumbnailURLUpgrader.upgrade(rawAvatar)
            let contents = carousel["contents"] as? [[String: Any]] ?? []
            let tracks = contents.compactMap { parseTrack($0) }
            if !tracks.isEmpty {
                let kind = classifySectionKind(title: headerTitle, strapline: headerStrapline)
                sections.append(YTHomeSection(
                    id: "\(headerTitle)-\(sections.count)",
                    title: headerTitle,
                    subtitle: headerStrapline,
                    avatarURL: headerAvatar,
                    kind: kind,
                    items: tracks
                ))
            }
        }
        return sections
    }

    private static func classifySectionKind(title: String, strapline: String?) -> YTHomeSectionKind {
        let joined = "\(title) \(strapline ?? "")".lowercased()
        if joined.contains("speed dial") || joined.contains("chọn nhanh") { return .speedDial }
        if joined.contains("music video") || joined.contains("video nhạc") { return .musicVideos }
        if joined.contains("live") || joined.contains("trực tiếp") { return .liveShows }
        if joined.contains("similar to") || joined.contains("tương tự") { return .artistSimilar }
        if joined.contains("more like") || joined.contains("giống như") { return .moreLikeArtist }
        if joined.contains("because you") || joined.contains("vì bạn") { return .becauseGenre }
        if joined.contains("try something") || joined.contains("thử nghe") { return .trySomethingNew }
        if joined.contains("new release") || joined.contains("new from") || joined.contains("phát hành mới") || joined.contains("mới") { return .newFromArtists }
        return .standard
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
                thumbnailURL: thumbs,
                subtitle: artistText.isEmpty ? nil : artistText
            )
        }

        if let responsive = dict["musicResponsiveListItemRenderer"] as? [String: Any] {
            let watchEndpoint = (((responsive["overlay"] as? [String: Any])?["musicItemThumbnailOverlayRenderer"] as? [String: Any])?["content"] as? [String: Any])?["musicPlayButtonRenderer"] as? [String: Any]
            let endpointWatch = (watchEndpoint?["playNavigationEndpoint"] as? [String: Any])?["watchEndpoint"] as? [String: Any]
            let videoId = (responsive["playlistItemData"] as? [String: Any])?["videoId"] as? String
                ?? endpointWatch?["videoId"] as? String
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
            let yearMatch = parts.first(where: { $0.trimmingCharacters(in: .whitespaces).count == 4 && Int($0.trimmingCharacters(in: .whitespaces)) != nil })
            let videoType = (((endpointWatch?["watchEndpointMusicSupportedConfigs"] as? [String: Any])?["watchEndpointMusicConfig"] as? [String: Any])?["musicVideoType"] as? String) ?? ""
            let isMV = videoType.contains("OMV") || videoType.contains("UGC")
            let thumbs = ThumbnailURLUpgrader.upgrade(((((responsive["thumbnail"] as? [String: Any])?["musicThumbnailRenderer"] as? [String: Any])?["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]])?.last?["url"] as? String)
            return YTTrackItem(
                id: videoId,
                title: title,
                artists: artists,
                durationSeconds: duration,
                thumbnailURL: thumbs,
                isVideo: isMV,
                subtitle: subtitle.isEmpty ? nil : subtitle,
                year: yearMatch?.trimmingCharacters(in: .whitespaces)
            )
        }

        if let twoRow = dict["musicTwoRowItemRenderer"] as? [String: Any] {
            let nav = twoRow["navigationEndpoint"] as? [String: Any]
            let watch = nav?["watchEndpoint"] as? [String: Any]
            let browse = nav?["browseEndpoint"] as? [String: Any]
            let videoId = (watch?["videoId"] as? String)
                ?? ((((twoRow["thumbnailOverlay"] as? [String: Any])?["musicItemThumbnailOverlayRenderer"] as? [String: Any])?["content"] as? [String: Any])?["musicPlayButtonRenderer"] as? [String: Any])
                    .flatMap { (($0["playNavigationEndpoint"] as? [String: Any])?["watchEndpoint"] as? [String: Any])?["videoId"] as? String }
            let browseId = browse?["browseId"] as? String
            guard let itemId = videoId ?? browseId, !itemId.isEmpty else { return nil }

            let title = (twoRow["title"] as? [String: Any]).flatMap { runsText($0) } ?? "Unknown"
            let subtitle = (twoRow["subtitle"] as? [String: Any]).flatMap { runsText($0) } ?? ""
            let parts = subtitle.components(separatedBy: " • ")
            let yearMatch = parts.first(where: { $0.trimmingCharacters(in: .whitespaces).count == 4 && Int($0.trimmingCharacters(in: .whitespaces)) != nil })
            let videoType = (((watch?["watchEndpointMusicSupportedConfigs"] as? [String: Any])?["watchEndpointMusicConfig"] as? [String: Any])?["musicVideoType"] as? String) ?? ""
            let isMV = videoType.contains("OMV") || videoType.contains("UGC")
            let thumbs = ThumbnailURLUpgrader.upgrade(((((twoRow["thumbnailRenderer"] as? [String: Any])?["musicThumbnailRenderer"] as? [String: Any])?["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]])?.last?["url"] as? String)
            return YTTrackItem(
                id: itemId,
                title: title,
                artists: splitArtists(parts.last == yearMatch ? (parts.first ?? subtitle) : subtitle),
                thumbnailURL: thumbs,
                isVideo: isMV,
                subtitle: subtitle.isEmpty ? nil : subtitle,
                year: yearMatch?.trimmingCharacters(in: .whitespaces),
                browseId: browseId
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
