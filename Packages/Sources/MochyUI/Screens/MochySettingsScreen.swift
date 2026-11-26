import MochyAudio
import MochyCore
import MochyDatabase
import MochySync
import SwiftUI
import UniformTypeIdentifiers
#if os(iOS) && canImport(WebKit)
import WebKit
#endif

/// Portable JSON FileDocument for sideload-friendly `TransferArchive` backup export to iOS Files / iCloud Drive.
public struct TransferArchiveDocument: FileDocument {
    public static var readableContentTypes: [UTType] { [.json] }
    public var data: Data

    public init(data: Data) {
        self.data = data
    }

    public init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// 1:1 Mochy Searchable Grouped-Card Settings Hub:
/// - Live `SettingsSearch` keyword filter across all 9 Mochy sections
/// - Profile Mini-Card -> `ProfileAndRecapScreen`
/// - Real `YouTubeLoginWebViewSheet`, Real Playlist URL/CSV Importer, Source Modules Manager,
///   Last.fm / Discord / OpenRouter / Mochy Link Integrations, Portable Backup `fileExporter`/`fileImporter` + WebDAV,
///   SQLite v47 Diagnostics & GPL-3.0 Attribution Credits
public struct MochySettingsScreen: View {
    @Bindable public var coordinator: AppCoordinator

    @State private var searchQuery = ""
    @State private var showProfile = false
    @State private var showAudioLab = false
    @State private var showYTLoginSheet = false
    @State private var showSetupWizard = false

    // Playlist Importer
    @State private var importURLInput = ""
    @State private var showCSVImporter = false

    // Modules
    @State private var newMonochromeServer = ""
    @State private var newWebModuleURL = ""

    // Secrets / Integrations
    @State private var lastFmApiKey = SecretVault.get(.lastFmApiKey) ?? ""
    @State private var lastFmSecret = SecretVault.get(.lastFmSharedSecret) ?? ""
    @State private var lastFmSession = SecretVault.get(.lastFmSessionKey) ?? ""
    @State private var discordToken = SecretVault.get(.discordToken) ?? ""
    @State private var openRouterKey = SecretVault.get(.aiApiKey) ?? ""
    @State private var webDavUrl = SecretVault.get(.webDavUrl) ?? ""
    @State private var webDavUser = SecretVault.get(.webDavUsername) ?? ""
    @State private var webDavPass = SecretVault.get(.webDavPassword) ?? ""
    @State private var integrationNotice: String?

    // Storage & Backup
    @State private var cacheBytes: Int64 = 0
    @State private var exportDoc: TransferArchiveDocument?
    @State private var showBackupExporter = false
    @State private var showBackupImporter = false
    @State private var backupNotice: String?
    @State private var schemaHealth: SchemaHealth?

    public init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Settings")
                        .font(.largeTitle.weight(.black))
                        .foregroundStyle(.white)

                    // Mochy SettingsSearch Bar
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search settings (EQ, Spotify, YouTube, Backup...)", text: $searchQuery)
                            .foregroundStyle(.white)
                        if !searchQuery.isEmpty {
                            Button { searchQuery = "" } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(11)
                    .background(MochyTheme.cardSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    // Profile Mini-Card
                    if matches("profile id card avatar recap stats") {
                        profileMiniCard
                    }

                    // 1. Account & YouTube Music Sync
                    if matches("account youtube login cookie sync undo") {
                        settingsCard(title: "YouTube Music Account & Sync", icon: "person.crop.circle.badge.checkmark") {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(coordinator.isSignedInToYouTube ? "Signed In" : "Guest Mode")
                                        .font(.subheadline.bold())
                                    Text(coordinator.isSignedInToYouTube ? "Authenticated InnerTube cookies active" : "Sign in to sync liked tracks & playlists")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if coordinator.isSignedInToYouTube {
                                    Button("Sign Out", role: .destructive) {
                                        Task { await coordinator.signOutYouTube() }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                } else {
                                    Button("Sign In") { showYTLoginSheet = true }
                                        .buttonStyle(.borderedProminent)
                                        .tint(MochyTheme.defaultAccent)
                                        .controlSize(.small)
                                }
                            }

                            Toggle("Exclude Imported Playlists from YT Sync", isOn: $coordinator.settings.ytExcludeImports)
                                .font(.subheadline)

                            HStack(spacing: 10) {
                                Button("Sync Library Now") {
                                    Task { await coordinator.runYouTubeLibrarySync() }
                                }
                                .buttonStyle(.bordered)
                                .disabled(!coordinator.isSignedInToYouTube)

                                if coordinator.canUndoLastSync {
                                    Button("Undo Last Sync", role: .destructive) {
                                        Task { await coordinator.undoYouTubeLibrarySync() }
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }

                            if let status = coordinator.syncStatusMessage {
                                Text(status).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }

                    // 2. Playlist Importer (Spotify / Apple Music / YTM / CSV)
                    if matches("import playlist spotify apple music youtube csv") {
                        settingsCard(title: "Playlist Importer", icon: "square.and.arrow.down.on.square") {
                            Text("Paste any public Spotify, Apple Music, or YouTube Music playlist URL (zero API keys needed).")
                                .font(.caption).foregroundStyle(.secondary)
                            HStack {
                                TextField("https://open.spotify.com/playlist/...", text: $importURLInput)
                                    .textFieldStyle(.roundedBorder)
                                Button("Import") {
                                    Task { await coordinator.runPlaylistImport(urlString: importURLInput) }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(MochyTheme.defaultAccent)
                                .disabled(importURLInput.trimmingCharacters(in: .whitespaces).isEmpty || coordinator.isImportingPlaylist)
                            }

                            Button {
                                showCSVImporter = true
                            } label: {
                                Label("Import CSV File (Exportify / TuneMyMusic)", systemImage: "doc.plaintext")
                            }
                            .buttonStyle(.bordered)
                            .disabled(coordinator.isImportingPlaylist)

                            if coordinator.isImportingPlaylist, let prog = coordinator.importProgress {
                                VStack(alignment: .leading, spacing: 4) {
                                    if prog.totalCount > 0 {
                                        ProgressView(value: Double(prog.matchedCount), total: Double(prog.totalCount))
                                            .tint(MochyTheme.defaultAccent)
                                    } else {
                                        ProgressView().tint(MochyTheme.defaultAccent)
                                    }
                                    Text("\(prog.stage) (\(prog.matchedCount)/\(prog.totalCount))")
                                        .font(.caption).foregroundStyle(.white.opacity(0.8))
                                }
                            } else if let msg = coordinator.importStatusMessage {
                                Text(msg).font(.caption).foregroundStyle(.green)
                            }
                        }
                    }

                    // 3. Appearance & 10 Player Styles
                    if matches("appearance theme player style home playlist blur oled black seekbar transport") {
                        settingsCard(title: "Appearance & Player Styles", icon: "paintbrush.pointed") {
                            Picker("Player Style", selection: $coordinator.settings.playerStyle) {
                                ForEach(PlayerStyle.allCases, id: \.self) { Text($0.displayName).tag($0) }
                            }
                            Picker("Home Layout", selection: $coordinator.settings.homeStyle) {
                                ForEach(HomeStyle.allCases, id: \.self) { Text($0.rawValue.replacingOccurrences(of: "_", with: " ").capitalized).tag($0) }
                            }
                            Picker("Playlist Style", selection: $coordinator.settings.playlistStyle) {
                                ForEach(PlaylistStyle.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                            }
                            Picker("Flagship Backdrop", selection: $coordinator.settings.flagshipBackground) {
                                ForEach(FlagshipBackground.allCases, id: \.self) { Text($0.rawValue.replacingOccurrences(of: "_", with: " ").capitalized).tag($0) }
                            }
                            Picker("Metal Blur Quality", selection: $coordinator.settings.blurQuality) {
                                Text("High (Metal Shaders)").tag(BlurQuality.high)
                                Text("Low (Battery Saver)").tag(BlurQuality.low)
                            }
                            Toggle("Pure Black OLED Background", isOn: $coordinator.settings.pureBlack)
                        }
                    }

                    // 4. Audio, Playback & DSP
                    if matches("audio quality dsp eq hrtf crossmix radio loudness mp4") {
                        settingsCard(title: "Audio & DSP Engine", icon: "slider.vertical.3") {
                            Picker("Audio Quality", selection: $coordinator.settings.audioQuality) {
                                ForEach(AudioQuality.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                            }
                            Toggle("Prefer Native MP4/AAC on iOS", isOn: $coordinator.settings.preferMp4OnIOS)
                            Toggle("Loudness Normalization (-14 LUFS)", isOn: $coordinator.settings.loudnessNormalizationEnabled)
                                .onChange(of: coordinator.settings.loudnessNormalizationEnabled) { _, _ in
                                    coordinator.player.syncDSPParameters()
                                }
                            Toggle("Infinite Radio Continuation", isOn: $coordinator.settings.infiniteQueueEnabled)
                            Toggle("Offline Mode (Local & Cached Only)", isOn: $coordinator.settings.offlineMode)

                            Button {
                                showAudioLab = true
                            } label: {
                                Label("Open Audio Lab (10-Band EQ, 3D Stage, Crossmix)", systemImage: "waveform.path.ecg")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(MochyTheme.defaultAccent)
                        }
                    }

                    // 5. Source Modules & Priority
                    if matches("modules monochrome flac jiosaavn youtube webmodule server order") {
                        settingsCard(title: "Source Modules & Priority", icon: "puzzlepiece.extension") {
                            Text("Resolution priority order (top resolves first):").font(.caption).foregroundStyle(.secondary)
                            ForEach(Array(coordinator.settings.sourceOrder.enumerated()), id: \.offset) { idx, sourceId in
                                HStack {
                                    Text("\(idx + 1). \(sourceId.capitalized)")
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Button {
                                        guard idx > 0 else { return }
                                        coordinator.settings.sourceOrder.swapAt(idx, idx - 1)
                                    } label: {
                                        Image(systemName: "arrow.up.circle")
                                    }
                                    .disabled(idx == 0)
                                    Button {
                                        guard idx + 1 < coordinator.settings.sourceOrder.count else { return }
                                        coordinator.settings.sourceOrder.swapAt(idx, idx + 1)
                                    } label: {
                                        Image(systemName: "arrow.down.circle")
                                    }
                                    .disabled(idx + 1 == coordinator.settings.sourceOrder.count)
                                }
                            }

                            Divider()
                            Text("Custom Monochrome FLAC Servers").font(.caption.bold())
                            HStack {
                                TextField("https://your-monochrome-node.tld", text: $newMonochromeServer)
                                    .textFieldStyle(.roundedBorder)
                                Button("Add") {
                                    let trimmed = newMonochromeServer.trimmingCharacters(in: .whitespacesAndNewlines)
                                    guard !trimmed.isEmpty else { return }
                                    coordinator.settings.customMonochromeServers.append(trimmed)
                                    newMonochromeServer = ""
                                    Task { await coordinator.syncRegisteredModulesFromSettings() }
                                }
                                .buttonStyle(.bordered)
                            }
                            ForEach(coordinator.settings.customMonochromeServers, id: \.self) { srv in
                                HStack {
                                    Text(srv).font(.caption).lineLimit(1)
                                    Spacer()
                                    Button(role: .destructive) {
                                        coordinator.settings.customMonochromeServers.removeAll { $0 == srv }
                                        Task { await coordinator.syncRegisteredModulesFromSettings() }
                                    } label: { Image(systemName: "trash") }
                                }
                            }

                            Divider()
                            Text("External WebStreamModule URLs").font(.caption.bold())
                            HStack {
                                TextField("https://module-host.example/api", text: $newWebModuleURL)
                                    .textFieldStyle(.roundedBorder)
                                Button("Add") {
                                    let trimmed = newWebModuleURL.trimmingCharacters(in: .whitespacesAndNewlines)
                                    guard !trimmed.isEmpty else { return }
                                    coordinator.settings.webModuleURLs.append(trimmed)
                                    newWebModuleURL = ""
                                    Task { await coordinator.syncRegisteredModulesFromSettings() }
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }

                    // 6. Lyrics & Translation
                    if matches("lyrics romanize translate openrouter ai language") {
                        settingsCard(title: "Lyrics & AI Translation", icon: "quote.bubble") {
                            Toggle("Auto Romanize CJK / Cyrillic / Devanagari", isOn: $coordinator.settings.lyricsRomanize)
                            Toggle("Enable Lyrics Translation", isOn: $coordinator.settings.lyricsTranslate)
                            HStack {
                                Text("Target Language").font(.subheadline)
                                Spacer()
                                Picker("", selection: $coordinator.settings.lyricsTranslationLanguage) {
                                    Text("Vietnamese (vi)").tag("vi")
                                    Text("English (en)").tag("en")
                                    Text("Japanese (ja)").tag("ja")
                                    Text("Korean (ko)").tag("ko")
                                    Text("Spanish (es)").tag("es")
                                    Text("French (fr)").tag("fr")
                                }
                            }
                            SecureField("OpenRouter API Key (Optional for AI Translation)", text: $openRouterKey)
                                .textFieldStyle(.roundedBorder)
                            Button("Save AI Key") {
                                try? SecretVault.set(openRouterKey, for: .aiApiKey)
                                integrationNotice = "Saved OpenRouter API Key to Keychain."
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }

                    // 7. Integrations (Last.fm, Discord, Mochy Link LAN)
                    if matches("lastfm scrobble discord presence mochy link lan bonjour") {
                        settingsCard(title: "Integrations & Mochy Link", icon: "antenna.radiowaves.left.and.right") {
                            Text("Last.fm Scrobbler (Bring Your Own Keys)").font(.caption.bold())
                            TextField("Last.fm API Key", text: $lastFmApiKey).textFieldStyle(.roundedBorder)
                            SecureField("Last.fm Shared Secret", text: $lastFmSecret).textFieldStyle(.roundedBorder)
                            SecureField("Last.fm Session Key", text: $lastFmSession).textFieldStyle(.roundedBorder)
                            HStack {
                                Button("Save & Flush Scrobbles") {
                                    try? SecretVault.set(lastFmApiKey, for: .lastFmApiKey)
                                    try? SecretVault.set(lastFmSecret, for: .lastFmSharedSecret)
                                    try? SecretVault.set(lastFmSession, for: .lastFmSessionKey)
                                    Task {
                                        await coordinator.scrobbler.flushStoredCredentials()
                                        let left = await coordinator.scrobbler.pendingCount()
                                        integrationNotice = "Last.fm credentials saved. Pending scrobbles: \(left)."
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }

                            Divider()
                            Text("Discord Rich Presence Gateway").font(.caption.bold())
                            SecureField("Discord User Token", text: $discordToken).textFieldStyle(.roundedBorder)
                            HStack {
                                Button("Save Token") {
                                    try? SecretVault.set(discordToken, for: .discordToken)
                                    integrationNotice = "Discord token saved to Keychain."
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                Button("Disconnect", role: .destructive) {
                                    Task { await coordinator.discord.disconnect() }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }

                            Divider()
                            Toggle("Mochy Link LAN Remote (`_mochy-link._tcp`)", isOn: Binding(
                                get: { coordinator.linkService.isHosting },
                                set: { enable in
                                    if enable {
                                        coordinator.linkService.startDiscoveryAndAdvertising()
                                    } else {
                                        coordinator.linkService.stop()
                                    }
                                }
                            ))
                            if !coordinator.linkService.discoveredPeers.isEmpty {
                                Text("Peers: \(coordinator.linkService.discoveredPeers.joined(separator: ", "))")
                                    .font(.caption).foregroundStyle(.cyan)
                            }
                            if let integrationNotice {
                                Text(integrationNotice).font(.caption).foregroundStyle(.green)
                            }
                        }
                    }

                    // 8. Storage, Cache & Portable Backup
                    if matches("storage cache clear backup export import icloud webdav archive") {
                        settingsCard(title: "Storage & Portable Backup", icon: "externaldrive") {
                            HStack {
                                Text("Audio Chunk & Offline Cache")
                                Spacer()
                                Text(ByteCountFormatter.string(fromByteCount: cacheBytes, countStyle: .file))
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }

                            Button("Clear Audio Cache", role: .destructive) {
                                Task {
                                    await coordinator.player.chunkCache.clearAll()
                                    cacheBytes = await coordinator.player.chunkCache.totalDiskUsageBytes()
                                    await coordinator.refreshDownloadedState()
                                    backupNotice = "Audio cache cleared."
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Divider()
                            Text("Portable JSON Transfer Archive (Works with Files / iCloud Drive on Sideloaded Builds)")
                                .font(.caption).foregroundStyle(.secondary)
                            HStack(spacing: 10) {
                                Button("Export Archive") {
                                    Task {
                                        if let data = try? await coordinator.cloudBackup.exportArchiveData() {
                                            exportDoc = TransferArchiveDocument(data: data)
                                            showBackupExporter = true
                                        }
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(MochyTheme.defaultAccent)

                                Button("Import Archive") {
                                    showBackupImporter = true
                                }
                                .buttonStyle(.bordered)
                            }

                            Divider()
                            Text("WebDAV Cloud Sync").font(.caption.bold())
                            TextField("https://dav.example.com/remote.php/dav/files/user/", text: $webDavUrl).textFieldStyle(.roundedBorder)
                            HStack {
                                TextField("Username", text: $webDavUser).textFieldStyle(.roundedBorder)
                                SecureField("Password", text: $webDavPass).textFieldStyle(.roundedBorder)
                            }
                            Button("Upload Backup to WebDAV") {
                                try? SecretVault.set(webDavUrl, for: .webDavUrl)
                                try? SecretVault.set(webDavUser, for: .webDavUsername)
                                try? SecretVault.set(webDavPass, for: .webDavPassword)
                                guard let endpoint = URL(string: webDavUrl) else {
                                    backupNotice = "Invalid WebDAV URL."
                                    return
                                }
                                Task {
                                    let ok = (try? await coordinator.cloudBackup.uploadWebDAV(endpoint: endpoint, username: webDavUser, password: webDavPass)) ?? false
                                    backupNotice = ok ? "Uploaded natch_backup.json to WebDAV." : "WebDAV upload failed."
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            if let backupNotice {
                                Text(backupNotice).font(.caption).foregroundStyle(.green)
                            }
                        }
                    }

                    // 9. Diagnostics & GPL-3.0 Attribution Credits
                    if matches("about diagnostics sqlite version gpl license credits mochy natch wizard") {
                        settingsCard(title: "Diagnostics & About Natch Music", icon: "info.circle") {
                            if let health = schemaHealth {
                                LabeledContent("SQLite Schema", value: "v\(health.userVersion) · \(health.tableCount) tables / \(health.viewCount) views")
                            }
                            LabeledContent("Active DSP Pipeline", value: "C++17 MTAudioProcessingTap + KEMAR HRTF")
                            LabeledContent("Streaming Proxy", value: "Native Swift NWListener LocalAudioProxy")

                            Button("Replay Setup Wizard") {
                                showSetupWizard = true
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Divider()
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Natch Music (iOS) — GNU GPL-3.0")
                                    .font(.caption.bold())
                                Text("Native Swift / SwiftUI iOS port faithful to realidkroo/Mochy-Music. Built upon the open-source foundations of Mochy Music, ViviMusic, Metrolist, InnerTune, Monochrome, AutoEq, and GRDB.swift. 100% free, zero ads, zero paywalls.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Spacer(minLength: 150)
                }
                .padding(16)
            }
            .background(MochyTheme.background(pureBlack: coordinator.settings.pureBlack).ignoresSafeArea())
            .task {
                cacheBytes = await coordinator.player.chunkCache.totalDiskUsageBytes()
                schemaHealth = try? coordinator.database.schemaHealthCheck()
            }
            .sheet(isPresented: $showProfile) { ProfileAndRecapScreen(coordinator: coordinator) }
            .sheet(isPresented: $showAudioLab) { AudioLabView(coordinator: coordinator) }
            .sheet(isPresented: $showYTLoginSheet) { YouTubeLoginWebViewSheet(coordinator: coordinator) }
            .sheet(isPresented: $showSetupWizard) {
                SetupWizardView(coordinator: coordinator) { showSetupWizard = false }
            }
            .fileImporter(
                isPresented: $showCSVImporter,
                allowedContentTypes: [.commaSeparatedText, .plainText],
                allowsMultipleSelection: false
            ) { result in
                if case let .success(urls) = result, let url = urls.first {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    if let text = try? String(contentsOf: url, encoding: .utf8) {
                        let name = url.deletingPathExtension().lastPathComponent
                        Task { await coordinator.runCSVImport(csvText: text, playlistName: name) }
                    }
                }
            }
            .fileExporter(
                isPresented: $showBackupExporter,
                document: exportDoc,
                contentType: .json,
                defaultFilename: "natch_music_backup"
            ) { result in
                switch result {
                case .success: backupNotice = "Exported portable Transfer Archive successfully."
                case let .failure(err): backupNotice = "Export failed: \(err.localizedDescription)"
                }
            }
            .fileImporter(
                isPresented: $showBackupImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                if case let .success(urls) = result, let url = urls.first {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    if let data = try? Data(contentsOf: url) {
                        Task {
                            if let count = try? await coordinator.cloudBackup.importArchiveData(data) {
                                coordinator.refreshLocalLibrary()
                                backupNotice = "Restored \(count) songs & playlists from archive."
                            } else {
                                backupNotice = "Failed to decode backup JSON."
                            }
                        }
                    }
                }
            }
        }
    }

    private var profileMiniCard: some View {
        Button {
            showProfile = true
        } label: {
            HStack(spacing: 14) {
                if let url = coordinator.profileAvatarURL() {
                    ArtworkImageView(urlString: url.absoluteString, cornerRadius: 24)
                        .frame(width: 48, height: 48)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(LinearGradient(colors: [MochyTheme.defaultAccent, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 48, height: 48)
                        .overlay(Image(systemName: "person.fill").foregroundStyle(.white))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(coordinator.settings.profileUsername.isEmpty ? "Listener" : coordinator.settings.profileUsername)
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                    Text("ID Card USR#\(coordinator.settings.profileCardNumber) · Recap & Stats")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .padding(14)
            .background(MochyTheme.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func settingsCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(.white)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MochyTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(MochyTheme.subtleBorder, lineWidth: 0.8)
        )
    }

    private func matches(_ keywords: String) -> Bool {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return q.isEmpty || keywords.contains(q)
    }
}

// MARK: - YouTube Music Interactive Login WebView Sheet

public struct YouTubeLoginWebViewSheet: View {
    @Bindable public var coordinator: AppCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var manualCookie = ""
    @State private var statusText = "Sign in to YouTube Music below, then tap Capture Session."

    public var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)

                #if os(iOS) && canImport(WebKit)
                YouTubeAuthWebView { cookie, visitor, dataSync in
                    Task {
                        await coordinator.applyYouTubeLogin(cookie: cookie, visitorData: visitor, dataSyncId: dataSync)
                        dismiss()
                    }
                }
                #else
                VStack(alignment: .leading, spacing: 10) {
                    Text("Paste `Cookie` header from music.youtube.com (must include `SAPISID`):")
                        .font(.caption)
                    TextEditor(text: $manualCookie)
                        .frame(height: 140)
                        .padding(8)
                        .background(MochyTheme.cardSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    Button("Save Cookie") {
                        Task {
                            await coordinator.applyYouTubeLogin(cookie: manualCookie, visitorData: nil, dataSyncId: nil)
                            dismiss()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(16)
                #endif
            }
            .background(.black)
            .navigationTitle("Sign in to YouTube Music")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

#if os(iOS) && canImport(WebKit)
private struct YouTubeAuthWebView: UIViewRepresentable {
    let onCaptured: (_ cookie: String, _ visitorData: String?, _ dataSyncId: String?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCaptured: onCaptured)
    }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        let web = WKWebView(frame: .zero, configuration: cfg)
        web.navigationDelegate = context.coordinator
        if let url = URL(string: "https://accounts.google.com/ServiceLogin?service=youtube&continue=https://music.youtube.com/") {
            web.load(URLRequest(url: url))
        }
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onCaptured: (String, String?, String?) -> Void
        private var captured = false

        init(onCaptured: @escaping (String, String?, String?) -> Void) {
            self.onCaptured = onCaptured
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !captured, let host = webView.url?.host?.lowercased(), host.contains("music.youtube.com") else {
                return
            }
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                let ytCookies = cookies.filter { $0.domain.contains("youtube.com") || $0.domain.contains("google.com") }
                guard ytCookies.contains(where: { $0.name == "SAPISID" || $0.name == "__Secure-3PAPISID" }) else {
                    return
                }
                let cookieHeader = ytCookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
                let js = "(function(){ try { return { v: window.ytcfg ? ytcfg.get('VISITOR_DATA') : null, d: window.ytcfg ? ytcfg.get('DATASYNC_ID') : null }; } catch(e){ return {}; } })()"
                webView.evaluateJavaScript(js) { res, _ in
                    guard let self, !self.captured else { return }
                    self.captured = true
                    let dict = res as? [String: Any]
                    self.onCaptured(cookieHeader, dict?["v"] as? String, dict?["d"] as? String)
                }
            }
        }
    }
}
#endif
