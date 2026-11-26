import Foundation
#if canImport(WebKit)
import WebKit
#endif

public struct PoTokenResult: Sendable, Equatable {
    public let playerRequestPoToken: String
    public let streamingDataPoToken: String

    public init(playerRequestPoToken: String, streamingDataPoToken: String) {
        self.playerRequestPoToken = playerRequestPoToken
        self.streamingDataPoToken = streamingDataPoToken
    }
}

public enum PoTokenError: Error, LocalizedError {
    case challengeFailed(String)
    case integrityFailed(String)
    case webViewUnavailable
    case mintTimeout

    public var errorDescription: String? {
        switch self {
        case let .challengeFailed(msg): return "BotGuard Create failed: \(msg)"
        case let .integrityFailed(msg): return "BotGuard GenerateIT failed: \(msg)"
        case .webViewUnavailable: return "WKWebView BotGuard runner unavailable."
        case .mintTimeout: return "PoToken BotGuard mint timed out."
        }
    }
}

/// Native iOS BotGuard `poToken` generator mirroring Mochy's `PoTokenGenerator` + `PoTokenWebView`.
public actor PoTokenGenerator {
    private static let mintCooldownSeconds: TimeInterval = 5 * 60
    private static let idleCloseSeconds: UInt64 = 60_000_000_000
    // Public YouTube Web BotGuard endpoint API key (non-secret client identifier from BgUtils).
    private static let jnnBaseURL = "https://www.youtube.com/api/jnn/v1"
    private static let requestKey = "O43z0dpjhgX20SCx4KAo"

    private let session: URLSession
    private var mintCooldownUntil: Date = .distantPast
    private var cachedSessionId: String?
    private var cachedSessionPoToken: String?
    private var expiresAt: Date = .distantPast
    private var idleTask: Task<Void, Never>?

    #if canImport(WebKit)
    private var runner: PoTokenWebRunner?
    #endif

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public var hasSessionToken: Bool {
        cachedSessionPoToken != nil && Date() < expiresAt
    }

    public var isInCooldown: Bool {
        Date() < mintCooldownUntil
    }

    public func releaseWebView() async {
        idleTask?.cancel()
        idleTask = nil
        #if canImport(WebKit)
        if let current = runner {
            runner = nil
            await current.close()
        }
        #endif
    }

    public func poTokenFor(videoId: String, sessionId: String) async -> PoTokenResult? {
        if isInCooldown {
            return nil
        }

        // shortcut: skips BotGuard WebView execution when running without WebKit / headless XCTest host; upgrade if headless WebKit harness is added.
        #if canImport(WebKit) && os(iOS)
        do {
            let result = try await mintPoTokenPair(videoId: videoId, sessionId: sessionId)
            scheduleIdleClose()
            return result
        } catch {
            mintCooldownUntil = Date().addingTimeInterval(Self.mintCooldownSeconds)
            return nil
        }
        #else
        return nil
        #endif
    }

    #if canImport(WebKit) && os(iOS)
    private func mintPoTokenPair(videoId: String, sessionId: String) async throws -> PoTokenResult {
        if runner == nil || Date() >= expiresAt || cachedSessionId != sessionId || cachedSessionPoToken == nil {
            if let old = runner {
                await old.close()
            }
            let webRunner = try await PoTokenWebRunner.create()
            let challenge = try await fetchBotGuardChallenge()
            let bgResponse = try await webRunner.runBotGuard(challengeJSON: challenge)
            let itResponse = try await fetchIntegrityToken(botguardResponse: bgResponse)

            let ttl = max(60, itResponse.ttlSeconds)
            try await webRunner.createMinter(integrityToken: itResponse.integrityToken)

            let sessionPot = try await webRunner.obtainToken(identifier: sessionId)
            self.runner = webRunner
            self.cachedSessionId = sessionId
            self.cachedSessionPoToken = sessionPot
            self.expiresAt = Date().addingTimeInterval(TimeInterval(ttl))
        }

        guard let activeRunner = runner, let sessionPot = cachedSessionPoToken else {
            throw PoTokenError.webViewUnavailable
        }
        let streamPot = try await activeRunner.obtainToken(identifier: videoId)
        return PoTokenResult(playerRequestPoToken: sessionPot, streamingDataPoToken: streamPot)
    }
    #endif

    private func fetchBotGuardChallenge() async throws -> [Any] {
        var req = URLRequest(url: URL(string: "\(Self.jnnBaseURL)/Create")!)
        req.httpMethod = "POST"
        req.setValue("application/json+protobuf", forHTTPHeaderField: "Content-Type")
        req.setValue("grpc-web-javascript/0.1", forHTTPHeaderField: "x-user-agent")
        req.setValue(YouTubeClient.userAgentWeb, forHTTPHeaderField: "User-Agent")
        req.httpBody = try JSONSerialization.data(withJSONObject: [Self.requestKey])

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let arr = try JSONSerialization.jsonObject(with: data) as? [Any], !arr.isEmpty else {
            throw PoTokenError.challengeFailed("Invalid Create response")
        }
        return arr
    }

    private func fetchIntegrityToken(botguardResponse: String) async throws -> (integrityToken: [Int], ttlSeconds: Int) {
        var req = URLRequest(url: URL(string: "\(Self.jnnBaseURL)/GenerateIT")!)
        req.httpMethod = "POST"
        req.setValue("application/json+protobuf", forHTTPHeaderField: "Content-Type")
        req.setValue("grpc-web-javascript/0.1", forHTTPHeaderField: "x-user-agent")
        req.setValue(YouTubeClient.userAgentWeb, forHTTPHeaderField: "User-Agent")
        req.httpBody = try JSONSerialization.data(withJSONObject: [Self.requestKey, botguardResponse])

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let arr = try JSONSerialization.jsonObject(with: data) as? [Any],
              let tokenB64 = arr.first as? String,
              let tokenData = Self.decodeBase64URL(tokenB64) else {
            throw PoTokenError.integrityFailed("Invalid GenerateIT payload")
        }
        let ttl = (arr.count > 1 ? (arr[1] as? NSNumber)?.intValue : nil) ?? 43_200
        return (tokenData.map { Int($0) }, ttl)
    }

    private func scheduleIdleClose() {
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.idleCloseSeconds)
            guard !Task.isCancelled else { return }
            await self?.releaseWebView()
        }
    }

    public static func decodeBase64URL(_ input: String) -> Data? {
        var base64 = input
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64)
    }
}

#if canImport(WebKit)
@MainActor
private final class PoTokenWebRunner: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private var loadContinuation: CheckedContinuation<Void, Error>?
    private var webPoSignalOutputJSON: Any?

    private override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        self.webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
        super.init()
        self.webView.navigationDelegate = self
    }

    static func create() async throws -> PoTokenWebRunner {
        guard let url = Bundle.module.url(forResource: "po_token", withExtension: "html"),
              let html = try? String(contentsOf: url, encoding: .utf8) else {
            throw PoTokenError.webViewUnavailable
        }
        let runner = PoTokenWebRunner()
        try await runner.loadHTML(html)
        return runner
    }

    private func loadHTML(_ html: String) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.loadContinuation = cont
            self.webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com/"))
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadContinuation?.resume()
        loadContinuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadContinuation?.resume(throwing: error)
        loadContinuation = nil
    }

    func runBotGuard(challengeJSON: [Any]) async throws -> String {
        guard let rawPayload = challengeJSON.first as? String,
              let data = rawPayload.data(using: .utf8),
              let parsed = try JSONSerialization.jsonObject(with: data) as? [Any],
              parsed.count >= 8 else {
            throw PoTokenError.challengeFailed("Unexpected BotGuard challenge envelope")
        }

        let challengeObject: [String: Any] = [
            "interpreterJavascript": ["privateDoNotAccessOrElseSafeScriptWrappedValue": parsed[4]],
            "globalName": parsed[7],
            "program": parsed[0],
        ]

        let script = """
        const res = await runBotGuard(challengeData);
        window.__mochyWebPoSignalOutput = res.webPoSignalOutput;
        return res.botguardResponse;
        """
        let result = try await webView.callAsyncJavaScript(
            script,
            arguments: ["challengeData": challengeObject],
            in: nil,
            contentWorld: .page
        )
        guard let responseString = result as? String else {
            throw PoTokenError.challengeFailed("BotGuard snapshot returned non-string")
        }
        webPoSignalOutputJSON = true
        return responseString
    }

    func createMinter(integrityToken: [Int]) async throws {
        guard webPoSignalOutputJSON != nil else {
            throw PoTokenError.webViewUnavailable
        }
        let script = """
        await createPoTokenMinter(window.__mochyWebPoSignalOutput, new Uint8Array(integrityBytes));
        return true;
        """
        _ = try await webView.callAsyncJavaScript(
            script,
            arguments: ["integrityBytes": integrityToken],
            in: nil,
            contentWorld: .page
        )
    }

    func obtainToken(identifier: String) async throws -> String {
        let idBytes = Array(identifier.utf8).map { Int($0) }
        let script = """
        const bytes = await obtainPoToken(new Uint8Array(identifierBytes));
        return btoa(String.fromCharCode(...bytes)).replace(/\\+/g, '-').replace(/\\//g, '_');
        """
        let result = try await webView.callAsyncJavaScript(
            script,
            arguments: ["identifierBytes": idBytes],
            in: nil,
            contentWorld: .page
        )
        guard let pot = result as? String, !pot.isEmpty else {
            throw PoTokenError.mintTimeout
        }
        return pot
    }

    func close() {
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
    }
}
#endif
