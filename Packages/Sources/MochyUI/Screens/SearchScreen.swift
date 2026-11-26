import MochyAudio
import MochyCore
import MochyDatabase
import MochyInnerTube
import MochySync
import SwiftUI

public enum SearchScope: String, CaseIterable {
    case online = "Online"
    case library = "Local & Library"
}

/// 1:1 Mochy Search Screen:
/// - Online & Local scopes, live suggestions, recent search history
/// - Direct URL paste detection (`Spotify` / `Apple Music` / `YouTube` -> 1-tap Playlist Import card with live progress!)
/// - Native `ShazamKit` recognition button + 1-tap `"Play Now"` matched track card
public struct SearchScreen: View {
    @Bindable public var coordinator: AppCoordinator
    @FocusState private var isSearchFieldFocused: Bool
    @State private var scope: SearchScope = .online

    public init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        let detectedLink = LinkImporter.parse(urlString: coordinator.searchQuery)
        let localMatches = filteredLocalSongs

        NavigationStack {
            VStack(spacing: 12) {
                // Search Input Bar
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.white.opacity(0.65))
                    TextField("Search songs, artists, or paste playlist URL...", text: $coordinator.searchQuery)
                        .focused($isSearchFieldFocused)
                        .foregroundStyle(.white)
                        .submitLabel(.search)
                        .onSubmit {
                            if detectedLink != nil {
                                Task { await coordinator.runPlaylistImport(urlString: coordinator.searchQuery) }
                            } else if scope == .online {
                                Task { await coordinator.runSearch() }
                            }
                        }
                        .onChange(of: coordinator.searchQuery) { _, newVal in
                            guard scope == .online, LinkImporter.parse(urlString: newVal) == nil else {
                                coordinator.searchSuggestions = []
                                return
                            }
                            Task { await coordinator.updateSuggestions(for: newVal) }
                        }

                    if !coordinator.searchQuery.isEmpty {
                        Button {
                            coordinator.searchQuery = ""
                            coordinator.searchSuggestions = []
                            coordinator.searchResults = []
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }

                    // ShazamKit Song Recognition Button
                    Button {
                        Task { await coordinator.shazam.recognizeCurrentMicrophone() }
                    } label: {
                        Image(systemName: coordinator.shazam.isListening ? "waveform.circle.fill" : "shazam.logo.fill")
                            .font(.title3)
                            .foregroundStyle(coordinator.shazam.isListening ? .white : .white.opacity(0.75))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(MochyTheme.cardSurface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 16)

                // Scope Segmented Picker
                Picker("Scope", selection: $scope) {
                    ForEach(SearchScope.allCases, id: \.self) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        // Direct URL Import Detection Banner
                        if let link = detectedLink {
                            importDetectedCard(target: link)
                        }

                        // ShazamKit Live Status & Matched Track Card
                        if coordinator.shazam.isListening || coordinator.shazam.latestMatch != nil {
                            shazamCard
                        }

                        if scope == .library {
                            if localMatches.isEmpty {
                                Text("No matching songs in your library.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 24)
                            } else {
                                ForEach(localMatches, id: \.id) { song in
                                    Button {
                                        coordinator.playLocalSong(song, allSongs: localMatches)
                                    } label: {
                                        HStack(spacing: 12) {
                                            ArtworkImageView(urlString: song.thumbnailUrl, cornerRadius: 8)
                                                .frame(width: 48, height: 48)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(song.title).font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                                                Text(song.isLocal ? "Local Audio" : (song.albumName ?? "Library"))
                                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                            }
                                            Spacer()
                                        }
                                        .padding(.vertical, 4)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        } else {
                            // Live Suggestions
                            if !coordinator.searchSuggestions.isEmpty && coordinator.searchResults.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Suggestions").font(.caption.bold()).foregroundStyle(.secondary)
                                    ForEach(coordinator.searchSuggestions, id: \.self) { sug in
                                        Button {
                                            Task { await coordinator.runSearch(query: sug) }
                                        } label: {
                                            HStack {
                                                Image(systemName: "magnifyingglass").font(.caption).foregroundStyle(.secondary)
                                                Text(sug).foregroundStyle(.white)
                                                Spacer()
                                            }
                                            .padding(.vertical, 8)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }

                            if coordinator.isSearching {
                                HStack {
                                    Spacer()
                                    ProgressView("Searching YouTube Music...")
                                        .tint(.white)
                                    Spacer()
                                }
                                .padding(.vertical, 24)
                            }

                            // Online Results
                            if !coordinator.searchResults.isEmpty {
                                ForEach(coordinator.searchResults) { track in
                                    HStack(spacing: 12) {
                                        Button {
                                            coordinator.playTrack(track, queueContext: coordinator.searchResults)
                                        } label: {
                                            HStack(spacing: 12) {
                                                ArtworkImageView(urlString: track.thumbnailURL, cornerRadius: 8)
                                                    .frame(width: 52, height: 52)
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(track.title)
                                                        .font(.subheadline.weight(.semibold))
                                                        .foregroundStyle(.white)
                                                        .lineLimit(1)
                                                    Text(track.artistDisplay)
                                                        .font(.caption)
                                                        .foregroundStyle(.white.opacity(0.66))
                                                        .lineLimit(1)
                                                }
                                                Spacer()
                                            }
                                        }
                                        .buttonStyle(.plain)

                                        Menu {
                                            Button {
                                                coordinator.player.playNext(PlaybackItem(ytTrack: track))
                                            } label: {
                                                Label("Play Next", systemImage: "text.insert")
                                            }
                                            Button {
                                                coordinator.player.appendToQueue(PlaybackItem(ytTrack: track))
                                            } label: {
                                                Label("Add to Queue", systemImage: "text.append")
                                            }
                                        } label: {
                                            Image(systemName: "ellipsis")
                                                .foregroundStyle(.white.opacity(0.65))
                                                .frame(width: 30, height: 30)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                            } else if coordinator.searchQuery.isEmpty && !coordinator.recentSearches.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Recent Searches").font(.headline).foregroundStyle(.white)
                                    ForEach(coordinator.recentSearches.prefix(12), id: \.self) { recent in
                                        Button {
                                            Task { await coordinator.runSearch(query: recent) }
                                        } label: {
                                            HStack {
                                                Image(systemName: "clock.arrow.circlepath").foregroundStyle(.secondary)
                                                Text(recent).foregroundStyle(.white)
                                                Spacer()
                                            }
                                            .padding(.vertical, 6)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }

                        Spacer(minLength: 150)
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.top, 12)
            .background(MochyTheme.background(pureBlack: coordinator.settings.pureBlack).ignoresSafeArea())
            .onChange(of: coordinator.searchFocusTrigger) { _, _ in
                isSearchFieldFocused = true
            }
        }
    }

    private var filteredLocalSongs: [SongEntity] {
        let q = coordinator.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return coordinator.librarySongs }
        return coordinator.librarySongs.filter {
            $0.title.lowercased().contains(q) || ($0.albumName?.lowercased().contains(q) ?? false)
        }
    }

    private func importDetectedCard(target: ImportedLinkTarget) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "square.and.arrow.down.on.square.fill")
                    .font(.title2)
                    .foregroundStyle(MochyTheme.defaultAccent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(target.service.rawValue.capitalized) \(target.kind.capitalized) Detected")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Import directly into your Natch library without login.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if coordinator.isImportingPlaylist, let prog = coordinator.importProgress {
                VStack(alignment: .leading, spacing: 6) {
                    if prog.totalCount > 0 {
                        ProgressView(value: Double(prog.matchedCount), total: Double(prog.totalCount))
                            .tint(MochyTheme.defaultAccent)
                    } else {
                        ProgressView().tint(MochyTheme.defaultAccent)
                    }
                    Text("\(prog.stage) (\(prog.matchedCount)/\(prog.totalCount))")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }
            } else {
                Button {
                    Task { await coordinator.runPlaylistImport(urlString: coordinator.searchQuery) }
                } label: {
                    Label("Import Now", systemImage: "arrow.down.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(MochyTheme.buttonFill)
            }

            if let msg = coordinator.importStatusMessage {
                Text(msg).font(.caption).foregroundStyle(.green)
            }
        }
        .padding(14)
        .background(MochyTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(MochyTheme.subtleBorder, lineWidth: 1)
        )
    }

    private var shazamCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "shazam.logo.fill").foregroundStyle(.white.opacity(0.85))
                Text(coordinator.shazam.statusMessage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
                if coordinator.shazam.isListening {
                    ProgressView().controlSize(.small)
                }
            }

            if let match = coordinator.shazam.latestMatch {
                HStack(spacing: 12) {
                    ArtworkImageView(urlString: match.coverArtUrl, cornerRadius: 8)
                        .frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(match.title).font(.subheadline.bold()).foregroundStyle(.white).lineLimit(1)
                        Text(match.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Button("Play Now") {
                        Task { await coordinator.playShazamMatch(match) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(MochyTheme.buttonFill)
                    .controlSize(.small)
                }
            }
        }
        .padding(12)
        .background(MochyTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
