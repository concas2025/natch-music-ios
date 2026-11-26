import MochyAudio
import MochyCore
import SwiftUI

public struct QueueSheetView: View {
    @Bindable public var coordinator: AppCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var showSaveDialog = false
    @State private var newPlaylistName = ""

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Quick playback mode toggles
                HStack(spacing: 10) {
                    modeToggleChip(
                        title: "Shuffle",
                        icon: "shuffle",
                        active: coordinator.player.shuffleEnabled
                    ) {
                        coordinator.player.shuffleEnabled.toggle()
                    }
                    modeToggleChip(
                        title: repeatLabel,
                        icon: coordinator.player.repeatMode == .one ? "repeat.1" : "repeat",
                        active: coordinator.player.repeatMode != .off
                    ) {
                        switch coordinator.player.repeatMode {
                        case .off: coordinator.player.repeatMode = .all
                        case .all: coordinator.player.repeatMode = .one
                        case .one: coordinator.player.repeatMode = .off
                        }
                    }
                    modeToggleChip(
                        title: "Radio",
                        icon: "dot.radiowaves.left.and.right",
                        active: coordinator.settings.infiniteQueueEnabled
                    ) {
                        coordinator.settings.infiniteQueueEnabled.toggle()
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                List {
                    if let current = coordinator.player.currentItem {
                        Section("Now Playing") {
                            queueRow(item: current, index: coordinator.player.currentIndex, isCurrent: true)
                        }
                    }

                    Section("Queue (\(coordinator.player.queue.count) tracks)") {
                        ForEach(Array(coordinator.player.queue.enumerated()), id: \.offset) { idx, item in
                            queueRow(item: item, index: idx, isCurrent: idx == coordinator.player.currentIndex)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    coordinator.player.jumpToQueueIndex(idx)
                                }
                        }
                        .onMove { from, to in
                            coordinator.player.moveQueueItem(fromOffsets: from, toOffset: to)
                        }
                        .onDelete { offsets in
                            for idx in offsets.sorted(by: >) {
                                coordinator.player.removeQueueItem(at: idx)
                            }
                        }
                    }
                }
                #if os(iOS)
                .listStyle(.insetGrouped)
                #endif
            }
            .navigationTitle("Up Next Queue")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Save Playlist") {
                        newPlaylistName = "Queue Mix \(Date().formatted(date: .abbreviated, time: .omitted))"
                        showSaveDialog = true
                    }
                    .disabled(coordinator.player.queue.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    HStack(spacing: 12) {
                        Button("Clear", role: .destructive) {
                            coordinator.player.clearUpcomingQueue()
                        }
                        .disabled(coordinator.player.queue.count <= 1)
                        #if os(iOS)
                        EditButton()
                        #endif
                    }
                }
            }
            .alert("Save Queue as Playlist", isPresented: $showSaveDialog) {
                TextField("Playlist name", text: $newPlaylistName)
                Button("Save") {
                    coordinator.createPlaylist(
                        name: newPlaylistName,
                        initialSongIds: coordinator.player.queue.map(\.id)
                    )
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .preferredColorScheme(.dark)
    }

    private var repeatLabel: String {
        switch coordinator.player.repeatMode {
        case .off: return "Repeat"
        case .all: return "All"
        case .one: return "One"
        }
    }

    private func queueRow(item: PlaybackItem, index: Int, isCurrent: Bool) -> some View {
        HStack(spacing: 12) {
            ArtworkImageView(urlString: item.thumbnailURL, cornerRadius: 8)
                .frame(width: 44, height: 44)
                .overlay {
                    if isCurrent {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(MochyTheme.defaultAccent, lineWidth: 2)
                    }
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline.weight(isCurrent ? .bold : .medium))
                    .foregroundStyle(isCurrent ? MochyTheme.defaultAccent : .white)
                    .lineLimit(1)
                Text(item.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if isCurrent {
                Image(systemName: coordinator.player.isPlaying ? "waveform" : "pause.fill")
                    .font(.caption.bold())
                    .foregroundStyle(MochyTheme.defaultAccent)
            } else if let dur = item.durationSeconds, dur > 0 {
                Text(MochyTimeFormatter.format(TimeInterval(dur)))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func modeToggleChip(title: String, icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(active ? MochyTheme.defaultAccent : MochyTheme.cardSurface)
                .foregroundStyle(.white)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
