import Foundation
import MochyUI

#if os(iOS) && canImport(ActivityKit)
import ActivityKit

/// Dynamic Island & Lock Screen Live Lyrics / Playback progress attributes (`ActivityKit`).
public struct MochyLiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var title: String
        public var artist: String
        public var activeLyricLine: String
        public var isPlaying: Bool
        public var progress: Double

        public init(title: String, artist: String, activeLyricLine: String, isPlaying: Bool, progress: Double) {
            self.title = title
            self.artist = artist
            self.activeLyricLine = activeLyricLine
            self.isPlaying = isPlaying
            self.progress = progress
        }
    }

    public var songId: String
    public init(songId: String) {
        self.songId = songId
    }
}
#endif

/// Coordinates iOS `ActivityKit` Live Activities cleanly without breaking free Apple ID sideloaded builds.
@MainActor
public final class LiveActivityCoordinator {
    public static let shared = LiveActivityCoordinator()

    #if os(iOS) && canImport(ActivityKit)
    private var currentActivity: Activity<MochyLiveActivityAttributes>?
    private var currentSongId: String?
    #endif

    private init() {}

    public func update(snapshot: LiveActivitySnapshot?) {
        #if os(iOS) && canImport(ActivityKit)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return
        }

        guard let snapshot else {
            endCurrentActivity()
            return
        }

        let state = MochyLiveActivityAttributes.ContentState(
            title: snapshot.title,
            artist: snapshot.artist,
            activeLyricLine: snapshot.activeLyricLine,
            isPlaying: snapshot.isPlaying,
            progress: snapshot.progress
        )
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(30))

        if let existing = currentActivity, currentSongId == snapshot.songId {
            Task {
                await existing.update(content)
            }
        } else {
            endCurrentActivity()
            let attrs = MochyLiveActivityAttributes(songId: snapshot.songId)
            do {
                currentActivity = try Activity.request(attributes: attrs, content: content, pushType: nil)
                currentSongId = snapshot.songId
            } catch {
                // Gracefully ignore when sideloaded without WidgetKit Live Activity extension.
                currentActivity = nil
                currentSongId = nil
            }
        }
        #endif
    }

    public func endCurrentActivity() {
        #if os(iOS) && canImport(ActivityKit)
        guard let existing = currentActivity else { return }
        currentActivity = nil
        currentSongId = nil
        Task {
            await existing.end(nil, dismissalPolicy: .immediate)
        }
        #endif
    }
}

#if os(iOS) && canImport(CarPlay)
import CarPlay

/// CarPlay Audio App scene delegate template exposing Now Playing & Library browsing.
public final class MochyCarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?

    public func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        let nowPlayingItem = CPListItem(text: "Now Playing", detailText: "Open Natch active queue")
        nowPlayingItem.handler = { [weak self] _, completion in
            self?.interfaceController?.pushTemplate(CPNowPlayingTemplate.shared, animated: true, completion: nil)
            completion()
        }
        let section = CPListSection(items: [nowPlayingItem])
        let root = CPListTemplate(title: "Natch Music", sections: [section])
        interfaceController.setRootTemplate(root, animated: true, completion: nil)
    }

    public func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        self.interfaceController = nil
    }
}
#endif
