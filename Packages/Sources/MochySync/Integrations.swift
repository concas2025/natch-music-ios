import CryptoKit
import Foundation
import MochyCore
import MochyDatabase
import Network
import Observation
#if os(iOS) && canImport(ShazamKit)
import ShazamKit
#endif

// MARK: - ShazamKit Native Audio Recognition

@MainActor
@Observable
public final class ShazamRecognizer {
    public private(set) var isListening = false
    public private(set) var latestMatch: RecognitionHistoryEntity?
    public private(set) var statusMessage: String = "Tap to recognize a song"

    private let database: MochyDatabase

    public init(database: MochyDatabase) {
        self.database = database
    }

    public func recognizeCurrentMicrophone() async {
        #if os(iOS) && canImport(ShazamKit)
        guard !isListening else { return }
        isListening = true
        statusMessage = "Listening with ShazamKit..."
        defer { isListening = false }

        let session = SHManagedSession()
        let result = await session.result()
        switch result {
        case let .match(match):
            guard let item = match.mediaItems.first else {
                statusMessage = "No track matched."
                return
            }
            let entry = RecognitionHistoryEntity(
                trackId: item.shazamID ?? UUID().uuidString,
                title: item.title ?? "Unknown Track",
                artist: item.artist ?? "Unknown Artist",
                coverArtUrl: item.artworkURL?.absoluteString,
                coverArtHqUrl: item.artworkURL?.absoluteString,
                genre: item.genres.first,
                shazamUrl: item.webURL?.absoluteString,
                appleMusicUrl: item.appleMusicURL?.absoluteString,
                isrc: item.isrc
            )
            try? database.saveRecognition(entry)
            latestMatch = entry
            statusMessage = "Matched: \(entry.title) — \(entry.artist)"
        case .noMatch:
            statusMessage = "No song detected. Try moving closer to the speaker."
        case let .error(error, _):
            statusMessage = "ShazamKit error: \(error.localizedDescription)"
        }
        #else
        statusMessage = "ShazamKit microphone capture is iOS-only."
        #endif
    }
}

// MARK: - Last.fm / Libre.fm Scrobbler (Zero hardcoded API keys)

public actor LastFmScrobbler {
    private var pendingQueue: [(artist: String, track: String, timestamp: Int)] = []
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public static func signParameters(_ params: [String: String], sharedSecret: String) -> String {
        let sorted = params.sorted { $0.key < $1.key }
        let concat = sorted.map { "\($0.key)\($0.value)" }.joined() + sharedSecret
        let digest = Insecure.MD5.hash(data: Data(concat.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public func enqueueScrobble(artist: String, track: String, timestamp: Int = Int(Date().timeIntervalSince1970)) {
        pendingQueue.append((artist, track, timestamp))
    }

    public func pendingCount() -> Int {
        pendingQueue.count
    }

    public func flushIfConfigured(apiKey: String?, sharedSecret: String?) async {
        guard let apiKey, !apiKey.isEmpty,
              let sharedSecret, !sharedSecret.isEmpty,
              let sessionKey = SecretVault.get(.lastFmSessionKey), !sessionKey.isEmpty,
              !pendingQueue.isEmpty else {
            return
        }

        let item = pendingQueue[0]
        var params: [String: String] = [
            "method": "track.scrobble",
            "api_key": apiKey,
            "sk": sessionKey,
            "artist": item.artist,
            "track": item.track,
            "timestamp": String(item.timestamp),
        ]
        params["api_sig"] = Self.signParameters(params, sharedSecret: sharedSecret)
        params["format"] = "json"

        guard let url = URL(string: "https://ws.audioscrobbler.com/2.0/") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        let body = params
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
        req.httpBody = body.data(using: .utf8)
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        if let (_, resp) = try? await session.data(for: req),
           let http = resp as? HTTPURLResponse,
           (200..<300).contains(http.statusCode) {
            pendingQueue.removeFirst()
        }
    }
}

// MARK: - Discord Rich Presence WebSocket Client

public actor DiscordPresenceClient {
    private var webSocketTask: URLSessionWebSocketTask?
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func updateListeningPresence(title: String, artist: String, durationSeconds: Int?) async {
        guard let token = SecretVault.get(.discordToken), !token.isEmpty else { return }
        if webSocketTask == nil {
            guard let url = URL(string: "wss://gateway.discord.gg/?v=10&encoding=json") else { return }
            let task = session.webSocketTask(with: url)
            task.resume()
            self.webSocketTask = task

            let identify: [String: Any] = [
                "op": 2,
                "d": [
                    "token": token,
                    "properties": ["os": "iOS", "browser": "Natch Music", "device": "iPhone"],
                ],
            ]
            if let data = try? JSONSerialization.data(withJSONObject: identify),
               let text = String(data: data, encoding: .utf8) {
                try? await task.send(.string(text))
            }
        }

        let nowMs = Int(Date().timeIntervalSince1970 * 1000)
        var timestamps: [String: Int] = ["start": nowMs]
        if let durationSeconds, durationSeconds > 0 {
            timestamps["end"] = nowMs + durationSeconds * 1000
        }
        let presence: [String: Any] = [
            "op": 3,
            "d": [
                "since": nowMs,
                "activities": [[
                    "name": "Natch Music",
                    "type": 2, // Listening
                    "details": title,
                    "state": artist,
                    "timestamps": timestamps,
                ]],
                "status": "online",
                "afk": false,
            ],
        ]
        if let data = try? JSONSerialization.data(withJSONObject: presence),
           let text = String(data: data, encoding: .utf8) {
            try? await webSocketTask?.send(.string(text))
        }
    }

    public func disconnect() {
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
    }
}

// MARK: - Mochy Link LAN Discovery & Remote Control (`_mochy-link._tcp` Bonjour)

@MainActor
@Observable
public final class MochyLinkService {
    public private(set) var isHosting = false
    public private(set) var discoveredPeers: [String] = []
    public private(set) var lastCommand: String?

    private var listener: NWListener?
    private var browser: NWBrowser?

    public init() {}

    public func startDiscoveryAndAdvertising(deviceName: String = "Natch iOS") {
        stop()
        do {
            let params = NWParameters.tcp
            let listener = try NWListener(using: params)
            listener.service = NWListener.Service(name: deviceName, type: "_mochy-link._tcp")
            listener.newConnectionHandler = { [weak self] connection in
                connection.start(queue: .main)
                connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, _ in
                    if let data, let cmd = String(data: data, encoding: .utf8) {
                        Task { @MainActor in self?.lastCommand = cmd }
                    }
                }
            }
            listener.start(queue: .main)
            self.listener = listener
            isHosting = true

            let browser = NWBrowser(for: .bonjour(type: "_mochy-link._tcp", domain: nil), using: .tcp)
            browser.browseResultsChangedHandler = { [weak self] results, _ in
                let names = results.compactMap { result -> String? in
                    if case let .service(name: name, type: _, domain: _, interface: _) = result.endpoint {
                        return name
                    }
                    return nil
                }
                Task { @MainActor in self?.discoveredPeers = names }
            }
            browser.start(queue: .main)
            self.browser = browser
        } catch {
            isHosting = false
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        browser?.cancel()
        browser = nil
        isHosting = false
    }
}
