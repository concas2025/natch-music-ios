import Foundation

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
