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

// MARK: - Last.fm / Libre.fm Scrobbler (Persistent Queue + Now Playing + Zero Hardcoded Keys)

public struct PendingScrobble: Codable, Sendable, Equatable {
    public let artist: String
    public let track: String
    public let timestamp: Int
}

public actor LastFmScrobbler {
    private var pendingQueue: [PendingScrobble] = []
    private let session: URLSession
    private let queueFileURL: URL

    public init(session: URLSession = .shared, queueFileURL: URL? = nil) {
        self.session = session
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let url = queueFileURL ?? caches.appendingPathComponent("natch_lastfm_queue.json")
        self.queueFileURL = url
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([PendingScrobble].self, from: data) {
            self.pendingQueue = decoded
        }
    }

    public static func signParameters(_ params: [String: String], sharedSecret: String) -> String {
        let sorted = params.sorted { $0.key < $1.key }
        let concat = sorted.map { "\($0.key)\($0.value)" }.joined() + sharedSecret
        let digest = Insecure.MD5.hash(data: Data(concat.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public func enqueueScrobble(artist: String, track: String, timestamp: Int = Int(Date().timeIntervalSince1970)) {
        pendingQueue.append(PendingScrobble(artist: artist, track: track, timestamp: timestamp))
        persistQueue()
    }

    public func pendingCount() -> Int {
        pendingQueue.count
    }

    public func updateNowPlaying(artist: String, track: String) async {
        guard let apiKey = SecretVault.get(.lastFmApiKey), !apiKey.isEmpty,
              let sharedSecret = SecretVault.get(.lastFmSharedSecret), !sharedSecret.isEmpty,
              let sessionKey = SecretVault.get(.lastFmSessionKey), !sessionKey.isEmpty else {
            return
        }
        var params: [String: String] = [
            "method": "track.updateNowPlaying",
            "api_key": apiKey,
            "sk": sessionKey,
            "artist": artist,
            "track": track,
        ]
        params["api_sig"] = Self.signParameters(params, sharedSecret: sharedSecret)
        params["format"] = "json"
        _ = await sendSignedPost(params: params)
    }

    public func flushStoredCredentials() async {
        await flushIfConfigured(
            apiKey: SecretVault.get(.lastFmApiKey),
            sharedSecret: SecretVault.get(.lastFmSharedSecret)
        )
    }

    public func flushIfConfigured(apiKey: String?, sharedSecret: String?) async {
        guard let apiKey, !apiKey.isEmpty,
              let sharedSecret, !sharedSecret.isEmpty,
              let sessionKey = SecretVault.get(.lastFmSessionKey), !sessionKey.isEmpty else {
            return
        }

        while !pendingQueue.isEmpty {
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

            let ok = await sendSignedPost(params: params)
            if ok {
                pendingQueue.removeFirst()
                persistQueue()
            } else {
                break
            }
        }
    }

    private func sendSignedPost(params: [String: String]) async -> Bool {
        guard let url = URL(string: "https://ws.audioscrobbler.com/2.0/") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "+&="))
        let body = params
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.value)" }
            .joined(separator: "&")
        req.httpBody = body.data(using: .utf8)
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        guard let (_, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            return false
        }
        return true
    }

    private func persistQueue() {
        if let data = try? JSONEncoder().encode(pendingQueue) {
            try? data.write(to: queueFileURL, options: .atomic)
        }
    }
}

// MARK: - Discord Rich Presence Gateway v10 Client (Hello + Heartbeat Loop + Auto-Reconnect)

public actor DiscordPresenceClient {
    private var webSocketTask: URLSessionWebSocketTask?
    private var heartbeatTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?
    private var lastSequence: Int?
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func updateListeningPresence(title: String, artist: String, durationSeconds: Int?) async {
        guard let token = SecretVault.get(.discordToken), !token.isEmpty else { return }
        if webSocketTask == nil {
            await connectAndIdentify(token: token)
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
        let sent = await sendJSON(presence)
        if !sent {
            disconnect()
            await connectAndIdentify(token: token)
            _ = await sendJSON(presence)
        }
    }

    public func clearPresence() async {
        guard webSocketTask != nil else { return }
        let clear: [String: Any] = [
            "op": 3,
            "d": [
                "since": NSNull(),
                "activities": [],
                "status": "online",
                "afk": false,
            ],
        ]
        _ = await sendJSON(clear)
    }

    public func disconnect() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        lastSequence = nil
    }

    private func connectAndIdentify(token: String) async {
        guard let url = URL(string: "wss://gateway.discord.gg/?v=10&encoding=json") else { return }
        let task = session.webSocketTask(with: url)
        task.resume()
        self.webSocketTask = task

        // Read `op: 10 Hello` packet to obtain the exact `heartbeat_interval` (ms).
        var intervalMs = 41_250
        if let msg = try? await task.receive(),
           let dict = decodeMessage(msg),
           (dict["op"] as? Int) == 10,
           let d = dict["d"] as? [String: Any],
           let hi = d["heartbeat_interval"] as? Int, hi >= 5_000 {
            intervalMs = hi
        }

        let identify: [String: Any] = [
            "op": 2,
            "d": [
                "token": token,
                "intents": 0,
                "properties": ["os": "iOS", "browser": "Natch Music", "device": "iPhone"],
            ],
        ]
        _ = await sendJSON(identify)

        startHeartbeat(intervalMs: intervalMs)
        startReceiveLoop(task: task)
    }

    private func startHeartbeat(intervalMs: Int) {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            let intervalNs = UInt64(max(5_000, intervalMs)) * 1_000_000
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: intervalNs)
                guard !Task.isCancelled, let self else { return }
                let seq: Any = await self.currentSequence() ?? NSNull()
                let sent = await self.sendJSON(["op": 1, "d": seq])
                if !sent {
                    await self.disconnect()
                    return
                }
            }
        }
    }

    private func startReceiveLoop(task: URLSessionWebSocketTask) {
        receiveTask?.cancel()
        receiveTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let message = try await task.receive()
                    guard let self else { return }
                    await self.handleGatewayMessage(message)
                } catch {
                    await self?.disconnect()
                    return
                }
            }
        }
    }

    private func handleGatewayMessage(_ message: URLSessionWebSocketTask.Message) async {
        guard let dict = decodeMessage(message) else { return }
        if let seq = dict["s"] as? Int {
            lastSequence = seq
        }
        if let op = dict["op"] as? Int, op == 1 {
            // Immediate heartbeat request from Discord
            let seq: Any = lastSequence ?? NSNull()
            _ = await sendJSON(["op": 1, "d": seq])
        } else if let op = dict["op"] as? Int, (op == 7 || op == 9) {
            disconnect()
        }
    }

    private func currentSequence() -> Int? { lastSequence }

    private func decodeMessage(_ message: URLSessionWebSocketTask.Message) -> [String: Any]? {
        let data: Data?
        switch message {
        case let .string(text): data = text.data(using: .utf8)
        case let .data(raw): data = raw
        @unknown default: data = nil
        }
        guard let data else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    @discardableResult
    private func sendJSON(_ payload: [String: Any]) async -> Bool {
        guard let task = webSocketTask,
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else {
            return false
        }
        do {
            try await task.send(.string(text))
            return true
        } catch {
            return false
        }
    }
}

// MARK: - Mochy Link LAN Discovery & Remote Control (`_mochy-link._tcp` Bonjour)

public struct MochyLinkCommand: Codable, Sendable, Equatable {
    public let action: String // "play", "pause", "toggle", "next", "previous", "seek"
    public let value: Double?

    public init(action: String, value: Double? = nil) {
        self.action = action
        self.value = value
    }
}

@MainActor
@Observable
public final class MochyLinkService {
    public private(set) var isHosting = false
    public private(set) var discoveredPeers: [String] = []
    public private(set) var lastCommand: String?
    public var onCommandReceived: ((MochyLinkCommand) -> Void)?

    private var listener: NWListener?
    private var browser: NWBrowser?
    private var activeConnections: [NWConnection] = []

    public init() {}

    public func startDiscoveryAndAdvertising(deviceName: String = "Natch iOS") {
        stop()
        do {
            let params = NWParameters.tcp
            let listener = try NWListener(using: params)
            listener.service = NWListener.Service(name: deviceName, type: "_mochy-link._tcp")
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.acceptConnection(connection)
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
        for conn in activeConnections { conn.cancel() }
        activeConnections.removeAll()
        listener?.cancel()
        listener = nil
        browser?.cancel()
        browser = nil
        isHosting = false
    }

    private func acceptConnection(_ connection: NWConnection) {
        activeConnections.append(connection)
        connection.start(queue: .main)
        receiveLoop(on: connection)
    }

    private func receiveLoop(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self else { return }
                if let data, !data.isEmpty {
                    if let decoded = try? JSONDecoder().decode(MochyLinkCommand.self, from: data) {
                        self.lastCommand = decoded.action
                        self.onCommandReceived?(decoded)
                    } else if let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                              !text.isEmpty {
                        self.lastCommand = text
                        self.onCommandReceived?(MochyLinkCommand(action: text.lowercased()))
                    }
                }
                if isComplete || error != nil {
                    connection.cancel()
                    self.activeConnections.removeAll { $0 === connection }
                } else {
                    self.receiveLoop(on: connection)
                }
            }
        }
    }
}
