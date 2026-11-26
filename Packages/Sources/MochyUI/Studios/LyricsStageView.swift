import MochyAudio
import MochyCore
import MochyLyrics
import SwiftUI

/// Custom SwiftUI `Layout` that wraps 100% of karaoke words onto multiple lines without ever truncating long lines.
public struct LyricsFlowLayout: Layout {
    public var horizontalSpacing: CGFloat
    public var verticalSpacing: CGFloat
    public var alignment: HorizontalAlignment

    public init(
        horizontalSpacing: CGFloat = 6,
        verticalSpacing: CGFloat = 5,
        alignment: HorizontalAlignment = .leading
    ) {
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
        self.alignment = alignment
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 320
        let rows = computeRows(maxWidth: maxWidth, subviews: subviews)
        let totalHeight = rows.reduce(CGFloat(0)) { acc, row in
            acc + row.height
        } + CGFloat(max(0, rows.count - 1)) * verticalSpacing
        let widest = rows.map(\.width).max() ?? 0
        return CGSize(width: min(maxWidth, widest), height: totalHeight)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(maxWidth: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            let startX: CGFloat
            switch alignment {
            case .trailing:
                startX = bounds.maxX - row.width
            case .center:
                startX = bounds.minX + (bounds.width - row.width) * 0.5
            default:
                startX = bounds.minX
            }

            var x = startX
            for item in row.items {
                let yOffset = (row.height - item.size.height) * 0.5
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y + yOffset),
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + horizontalSpacing
            }
            y += row.height + verticalSpacing
        }
    }

    private struct RowItem {
        let index: Int
        let size: CGSize
    }

    private struct Row {
        var items: [RowItem] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func computeRows(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()

        for idx in subviews.indices {
            let sz = subviews[idx].sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            let addedWidth = current.items.isEmpty ? sz.width : (current.width + horizontalSpacing + sz.width)
            if !current.items.isEmpty && addedWidth > maxWidth {
                rows.append(current)
                current = Row(items: [RowItem(index: idx, size: sz)], width: sz.width, height: sz.height)
            } else {
                current.items.append(RowItem(index: idx, size: sz))
                current.width = addedWidth
                current.height = max(current.height, sz.height)
            }
        }
        if !current.items.isEmpty {
            rows.append(current)
        }
        return rows
    }
}

/// 1:1 Mochy Lyrics Stage:
/// - Full wrapping `LyricsFlowLayout` (zero word truncation)
/// - Word-timed gradient fill sweep + sustained-note bloom glow + vertical lift
/// - Animated `LyricsInterludeDots` on gaps >= 5000ms
/// - Duet `v1`/`v2` left/right alignment & background vocals styling
/// - Distance blur on non-active lines
/// - Persistent `lyricsOffset` DB controls + 1-tap `Auto-Sync` via `LyricsAutoSync`
public struct LyricsStageView: View {
    @Bindable public var coordinator: AppCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var isAutoSyncing = false
    @State private var autoSyncMessage: String?

    public var body: some View {
        let accent = coordinator.paletteColors.first ?? MochyTheme.defaultAccent

        NavigationStack {
            ZStack {
                AmbientBackdropView(
                    colors: coordinator.paletteColors,
                    style: .ambient,
                    blurQuality: coordinator.settings.blurQuality,
                    isPaused: !coordinator.player.isPlaying
                )

                VStack(spacing: 0) {
                    if coordinator.isLoadingLyrics {
                        Spacer()
                        ProgressView("Fetching synced lyrics...")
                            .tint(.white)
                            .foregroundStyle(.white.opacity(0.85))
                        Spacer()
                    } else if let doc = coordinator.currentLyrics, !doc.lines.isEmpty {
                        lyricsScrollBody(doc: doc, accent: accent)
                    } else {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: "text.quote")
                                .font(.system(size: 40))
                                .foregroundStyle(.white.opacity(0.45))
                            Text("No lyrics found for this track.")
                                .font(.headline)
                                .foregroundStyle(.white.opacity(0.8))
                            Button("Retry Lookup") {
                                Task { await coordinator.loadLyricsForCurrentTrack(forceRefresh: true) }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(accent)
                        }
                        Spacer()
                    }

                    lyricsControlDock(accent: accent)
                }
            }
            .navigationTitle(coordinator.player.currentItem?.title ?? "Lyrics Stage")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Menu {
                        Toggle("Romanization", isOn: $coordinator.settings.lyricsRomanize)
                        Toggle("AI Translation (\(coordinator.settings.lyricsTranslationLanguage.uppercased()))", isOn: $coordinator.settings.lyricsTranslate)
                        Picker("Motion Style", selection: $coordinator.settings.lyricsMotionStyle) {
                            ForEach(LyricsMotionStyle.allCases, id: \.self) { m in
                                Text(m.rawValue.capitalized).tag(m)
                            }
                        }
                        Divider()
                        Button("Force Refresh Lyrics") {
                            Task { await coordinator.loadLyricsForCurrentTrack(forceRefresh: true) }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .onChange(of: coordinator.settings.lyricsRomanize) { _, _ in
                Task { await coordinator.loadLyricsForCurrentTrack() }
            }
            .onChange(of: coordinator.settings.lyricsTranslate) { _, _ in
                Task { await coordinator.loadLyricsForCurrentTrack() }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func lyricsScrollBody(doc: LyricsDocument, accent: Color) -> some View {
        let nowMs = Int(coordinator.player.currentTime * 1000) + coordinator.currentLyricsOffsetMs
        let activeIdx = doc.isSynced
            ? (doc.lines.lastIndex(where: { $0.startMs <= nowMs }) ?? -1)
            : -1

        return ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 22) {
                    // Intro interlude dots if first line starts >= 5s in
                    if doc.isSynced, let first = doc.lines.first, first.startMs >= 5000, nowMs < first.startMs {
                        LyricsInterludeDots(
                            progress: Double(max(0, nowMs)) / Double(max(1, first.startMs)),
                            accent: accent
                        )
                    }

                    ForEach(Array(doc.lines.enumerated()), id: \.offset) { idx, line in
                        let isActive = idx == activeIdx
                        let distance = activeIdx >= 0 ? abs(idx - activeIdx) : 0
                        let blurRadius: CGFloat = doc.isSynced && !isActive ? min(3.2, CGFloat(distance) * 0.85) : 0

                        // Check instrumental interlude >= 5000ms before this line
                        if doc.isSynced, idx > 0 {
                            let prev = doc.lines[idx - 1]
                            let prevEnd = prev.endMs ?? (prev.startMs + 2500)
                            let gap = line.startMs - prevEnd
                            if gap >= 5000 && nowMs >= prevEnd && nowMs < line.startMs {
                                LyricsInterludeDots(
                                    progress: Double(nowMs - prevEnd) / Double(max(1, gap)),
                                    accent: accent
                                )
                            }
                        }

                        lyricLineRow(
                            line: line,
                            nowMs: nowMs,
                            isActive: isActive,
                            isSynced: doc.isSynced,
                            accent: accent
                        )
                        .blur(radius: blurRadius)
                        .opacity(isActive || !doc.isSynced ? 1.0 : max(0.32, 0.72 - Double(distance) * 0.12))
                        .id(idx)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if doc.isSynced {
                                let targetSec = max(0, Double(line.startMs - coordinator.currentLyricsOffsetMs) / 1000.0)
                                coordinator.player.seek(to: targetSec)
                            }
                        }
                    }

                    HStack {
                        Text("Source: \(doc.sourceProvider)")
                        if doc.isWordTimed {
                            Text("· Word-Sync")
                        }
                        if doc.hasDuet {
                            Text("· Duet")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.top, 16)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 48)
            }
            .onChange(of: activeIdx) { _, newIdx in
                guard newIdx >= 0 else { return }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                    proxy.scrollTo(newIdx, anchor: .center)
                }
            }
        }
    }

    private func lyricLineRow(
        line: LyricsLine,
        nowMs: Int,
        isActive: Bool,
        isSynced: Bool,
        accent: Color
    ) -> some View {
        let isRightDuet = line.agent == .v2
        let hAlign: HorizontalAlignment = isRightDuet ? .trailing : .leading
        let textAlign: TextAlignment = isRightDuet ? .trailing : .leading
        let baseSize: CGFloat = line.isBackground ? 17 : (isActive ? 26 : 22)

        return VStack(alignment: hAlign, spacing: 6) {
            if !line.words.isEmpty && isSynced {
                LyricsFlowLayout(horizontalSpacing: 6, verticalSpacing: 4, alignment: hAlign) {
                    ForEach(line.words) { word in
                        karaokeWordView(word: word, nowMs: nowMs, fontSize: baseSize, accent: accent)
                    }
                }
                .frame(maxWidth: .infinity, alignment: isRightDuet ? .trailing : .leading)
            } else {
                Text(line.text)
                    .font(.system(size: baseSize, weight: isActive ? .heavy : .bold, design: .rounded))
                    .foregroundStyle(isActive ? .white : .white.opacity(0.82))
                    .multilineTextAlignment(textAlign)
                    .frame(maxWidth: .infinity, alignment: isRightDuet ? .trailing : .leading)
                    .scaleEffect(isActive ? 1.02 : 1.0, anchor: isRightDuet ? .trailing : .leading)
                    .animation(.spring(response: 0.30, dampingFraction: 0.80), value: isActive)
            }

            if coordinator.settings.lyricsRomanize, let rom = line.romanized, !rom.isEmpty {
                Text(rom)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(isActive ? 0.85 : 0.55))
                    .multilineTextAlignment(textAlign)
                    .frame(maxWidth: .infinity, alignment: isRightDuet ? .trailing : .leading)
            }

            if coordinator.settings.lyricsTranslate, let trans = line.translated, !trans.isEmpty {
                Text(trans)
                    .font(.subheadline.italic())
                    .foregroundStyle(accent.opacity(isActive ? 0.98 : 0.65))
                    .multilineTextAlignment(textAlign)
                    .frame(maxWidth: .infinity, alignment: isRightDuet ? .trailing : .leading)
            }
        }
    }

    private func karaokeWordView(word: LyricsWord, nowMs: Int, fontSize: CGFloat, accent: Color) -> some View {
        let span = max(1, word.endMs - word.startMs)
        let progress = max(0.0, min(1.0, Double(nowMs - word.startMs) / Double(span)))
        let isSinging = nowMs >= word.startMs && nowMs <= word.endMs
        let isSustained = span >= 650 && isSinging
        let glowColor = coordinator.settings.lyricsMotionStyle == .neon ? accent : Color.white

        return Text(word.text)
            .font(.system(size: word.isBackground ? fontSize * 0.82 : fontSize, weight: .heavy, design: .rounded))
            .foregroundStyle(.white.opacity(0.32))
            .overlay {
                GeometryReader { g in
                    Text(word.text)
                        .font(.system(size: word.isBackground ? fontSize * 0.82 : fontSize, weight: .heavy, design: .rounded))
                        .foregroundStyle(coordinator.settings.lyricsMotionStyle == .neon && isSinging ? accent : .white)
                        .frame(width: g.size.width, alignment: .leading)
                        .mask(alignment: .leading) {
                            Rectangle()
                                .frame(width: g.size.width * CGFloat(progress))
                        }
                }
            }
            .offset(y: isSinging ? -2.2 : 0)
            .shadow(color: isSustained ? glowColor.opacity(0.75) : .clear, radius: isSustained ? 10 : 0)
            .animation(.easeOut(duration: 0.12), value: isSinging)
    }

    private func lyricsControlDock(accent: Color) -> some View {
        VStack(spacing: 8) {
            if let autoSyncMessage {
                Text(autoSyncMessage)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(accent)
            }

            HStack(spacing: 10) {
                Button("-100ms") {
                    coordinator.updateCurrentLyricsOffset(coordinator.currentLyricsOffsetMs - 100)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    coordinator.updateCurrentLyricsOffset(0)
                } label: {
                    Text("\(coordinator.currentLyricsOffsetMs >= 0 ? "+" : "")\(coordinator.currentLyricsOffsetMs) ms")
                        .font(.caption.monospacedDigit().bold())
                        .foregroundStyle(.white)
                        .frame(minWidth: 68)
                }
                .buttonStyle(.plain)

                Button("+100ms") {
                    coordinator.updateCurrentLyricsOffset(coordinator.currentLyricsOffsetMs + 100)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Button {
                    Task {
                        isAutoSyncing = true
                        defer { isAutoSyncing = false }
                        if let est = await coordinator.autoSyncCurrentLyrics() {
                            autoSyncMessage = "Auto-Sync applied: \(est >= 0 ? "+" : "")\(est) ms"
                        } else {
                            autoSyncMessage = "Auto-Sync needs a cached or local audio track."
                        }
                    }
                } label: {
                    if isAutoSyncing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Auto-Sync", systemImage: "waveform.badge.magnifyingglass")
                            .font(.caption.bold())
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .controlSize(.small)
                .disabled(isAutoSyncing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(.ultraThinMaterial)
    }
}

/// Animated 3-dot vocal interlude indicator shown on gaps >= 5000ms.
private struct LyricsInterludeDots: View {
    let progress: Double
    let accent: Color

    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { idx in
                let threshold = Double(idx + 1) / 3.0
                let active = progress >= (threshold - 0.33)
                Circle()
                    .fill(active ? accent : Color.white.opacity(0.28))
                    .frame(width: active ? 10 : 8, height: active ? 10 : 8)
                    .scaleEffect(active ? 1.15 : 0.9)
                    .animation(.easeInOut(duration: 0.35), value: active)
            }
        }
        .padding(.vertical, 6)
    }
}
