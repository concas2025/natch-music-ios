import MochyAudio
import MochyCore
import MochyDatabase
import SwiftUI
#if os(iOS) && canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// 1:1 Mochy Music floating frosted-glass player action menu (`...`).
public struct PlayerActionMenuOverlay: View {
    @Bindable public var coordinator: AppCoordinator
    @Binding public var isPresented: Bool
    public let onOpenAudioLab: () -> Void
    public let onOpenStylePicker: () -> Void
    public let onOpenAddToPlaylist: () -> Void
    public let onOpenStreamInfo: () -> Void
    public let onOpenSleepTimer: () -> Void
    public let onOpenLyricsWithOffset: () -> Void
    public let onOpenShare: () -> Void

    public init(
        coordinator: AppCoordinator,
        isPresented: Binding<Bool>,
        onOpenAudioLab: @escaping () -> Void,
        onOpenStylePicker: @escaping () -> Void,
        onOpenAddToPlaylist: @escaping () -> Void,
        onOpenStreamInfo: @escaping () -> Void,
        onOpenSleepTimer: @escaping () -> Void,
        onOpenLyricsWithOffset: @escaping () -> Void,
        onOpenShare: @escaping () -> Void
    ) {
        self.coordinator = coordinator
        self._isPresented = isPresented
        self.onOpenAudioLab = onOpenAudioLab
        self.onOpenStylePicker = onOpenStylePicker
        self.onOpenAddToPlaylist = onOpenAddToPlaylist
        self.onOpenStreamInfo = onOpenStreamInfo
        self.onOpenSleepTimer = onOpenSleepTimer
        self.onOpenLyricsWithOffset = onOpenLyricsWithOffset
        self.onOpenShare = onOpenShare
    }

    public var body: some View {
        let item = coordinator.player.currentItem
        let liked = coordinator.isLiked(songId: item?.id)
        let disliked = item.map { coordinator.dislikedSongIds.contains($0.id) } ?? false
        let downloaded = item.map { coordinator.downloadedSongIds.contains($0.id) } ?? false
        let coverTint = coordinator.paletteColors.first ?? Color(white: 0.22)

        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { dismissMenu() }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // Top 3 horizontal quick actions
                    HStack(spacing: 6) {
                        topQuickButton(
                            icon: liked ? "hand.thumbsup.fill" : "hand.thumbsup",
                            label: "Thích",
                            active: liked
                        ) {
                            if let id = item?.id { coordinator.toggleLike(songId: id) }
                            dismissMenu()
                        }
                        topQuickButton(
                            icon: disliked ? "hand.thumbsdown.fill" : "hand.thumbsdown",
                            label: "Không thích",
                            active: disliked
                        ) {
                            coordinator.toggleDislikeCurrentTrack()
                            dismissMenu()
                        }
                        topQuickButton(
                            icon: "square.and.arrow.up",
                            label: "Chia sẻ",
                            active: false
                        ) {
                            dismissMenu()
                            onOpenShare()
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 12)
                    .padding(.bottom, 10)

                    menuDivider

                    // Group 1: Audio & Style
                    menuRow(icon: "slider.vertical.3", title: "Audio Lab") {
                        dismissMenu()
                        onOpenAudioLab()
                    }
                    menuRow(icon: "arrow.up.circle", title: "Nâng cấp chất lượng") {
                        coordinator.settings.audioQuality = .high
                        coordinator.player.forceSwitchProvider(to: "monochrome")
                        coordinator.showMenuToast("Upgrading stream quality...")
                        dismissMenu()
                    }
                    menuRow(icon: "film", title: "Chuyển đổi thành video") {
                        coordinator.settings.playerStyle = .video
                        Task { await coordinator.loadVideoStreamsForCurrent() }
                        dismissMenu()
                    }
                    menuRow(icon: "sparkles.rectangle.stack", title: "Kiểu trình phát") {
                        dismissMenu()
                        onOpenStylePicker()
                    }

                    menuDivider

                    // Group 2: Queue & Radio
                    menuRow(icon: "text.badge.plus", title: "Thêm vào danh sách phát") {
                        dismissMenu()
                        onOpenAddToPlaylist()
                    }
                    menuRow(icon: "dot.radiowaves.left.and.right", title: "Phát radio") {
                        dismissMenu()
                        Task { await coordinator.startRadioForCurrentTrack() }
                    }
                    menuRow(icon: "text.insert", title: "Phát tiếp theo") {
                        if let item {
                            coordinator.player.playNext(item)
                            coordinator.showMenuToast("Queued to play next")
                        }
                        dismissMenu()
                    }
                    menuRow(icon: "text.append", title: "Thêm vào hàng đợi") {
                        if let item {
                            coordinator.player.appendToQueue(item)
                            coordinator.showMenuToast("Added to queue")
                        }
                        dismissMenu()
                    }

                    menuDivider

                    // Group 3: Offline & Cache
                    menuRow(
                        icon: downloaded ? "checkmark.circle.fill" : "arrow.down.circle",
                        title: downloaded ? "Đã tải xuống" : "Tải xuống"
                    ) {
                        dismissMenu()
                        Task { await coordinator.downloadCurrentTrackToCache() }
                    }
                    menuRow(icon: "trash", title: "Xóa khỏi bộ nhớ đệm") {
                        dismissMenu()
                        Task { await coordinator.clearCacheForCurrentTrack() }
                    }

                    menuDivider

                    // Group 4: Navigation, Info & Tools
                    menuRow(icon: "square.stack", title: "Mở album") {
                        let q = item?.album ?? item?.title ?? ""
                        dismissMenu()
                        if !q.isEmpty { coordinator.openInAppSearch(query: q) }
                    }
                    menuRow(icon: "person.circle", title: "Mở nghệ sĩ") {
                        let q = item?.artist ?? ""
                        dismissMenu()
                        if !q.isEmpty { coordinator.openInAppSearch(query: q) }
                    }
                    menuRow(icon: "info.circle", title: "Thông tin bài hát") {
                        dismissMenu()
                        onOpenStreamInfo()
                    }
                    menuRow(icon: "moon.zzz", title: timerLabel) {
                        dismissMenu()
                        onOpenSleepTimer()
                    }
                    menuRow(icon: "waveform.path", title: "Lyrics offset") {
                        dismissMenu()
                        onOpenLyricsWithOffset()
                    }
                    menuRow(icon: "doc.on.clipboard", title: "Sao chép nhật ký") {
                        copyText(coordinator.buildCurrentTrackDiagnosticLog())
                        coordinator.showMenuToast("Đã sao chép nhật ký")
                        dismissMenu()
                    }
                }
                .padding(.bottom, 8)
            }
            .frame(maxWidth: 296, maxHeight: 580)
            .background(
                ZStack {
                    Color.black.opacity(0.42)
                    coverTint.opacity(0.28)
                }
                .background(.ultraThinMaterial)
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.8)
            )
            .shadow(color: .black.opacity(0.45), radius: 24, y: 12)
            .padding(.top, 92)
            .padding(.trailing, 18)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .topTrailing)))
    }

    private var timerLabel: String {
        if let rem = coordinator.player.sleepTimerRemainingSeconds {
            return "Hẹn giờ tắt (\(max(1, rem / 60))p)"
        }
        return "Hẹn giờ tắt"
    }

    private var menuDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.10))
            .frame(height: 0.6)
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
    }

    private func topQuickButton(
        icon: String,
        label: String,
        active: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(active ? .black : .white)
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(active ? .black : .white.opacity(0.88))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(active ? Color.white : Color.white.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func menuRow(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(width: 22)
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(1)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10.5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func dismissMenu() {
        withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
            isPresented = false
        }
    }

    private func copyText(_ text: String) {
        #if os(iOS) && canImport(UIKit)
        UIPasteboard.general.string = text
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

/// Picker sheet for adding the current track to any local playlist or creating a new one.
public struct AddToPlaylistPickerSheet: View {
    @Bindable public var coordinator: AppCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var newPlaylistName = ""

    public init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        NavigationStack {
            List {
                Section("Create New Playlist") {
                    HStack(spacing: 10) {
                        TextField("Playlist name...", text: $newPlaylistName)
                            .foregroundStyle(.white)
                        Button("Create") {
                            let trimmed = newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            coordinator.createPlaylist(name: trimmed)
                            if let created = coordinator.libraryPlaylists.last(where: { $0.name == trimmed }) {
                                coordinator.addCurrentTrackToPlaylist(playlistId: created.id)
                            }
                            newPlaylistName = ""
                            dismiss()
                        }
                        .disabled(newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                Section("Your Playlists") {
                    if coordinator.libraryPlaylists.isEmpty {
                        Text("No playlists yet — create one above.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(coordinator.libraryPlaylists, id: \.id) { playlist in
                            Button {
                                coordinator.addCurrentTrackToPlaylist(playlistId: playlist.id)
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    ArtworkImageView(urlString: playlist.thumbnailUrl, cornerRadius: 8)
                                        .frame(width: 42, height: 42)
                                    Text(playlist.name)
                                        .foregroundStyle(.white)
                                    Spacer()
                                    Image(systemName: "plus.circle")
                                        .foregroundStyle(.white.opacity(0.65))
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add to Playlist")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .preferredColorScheme(.dark)
    }
}
