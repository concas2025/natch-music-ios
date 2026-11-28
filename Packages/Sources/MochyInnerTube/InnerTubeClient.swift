import Foundation
import MochyCore

public enum InnerTubeError: Error, LocalizedError, Equatable {
    case invalidURL
    case httpStatus(Int, String?)
    case decodingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid InnerTube endpoint URL."
        case let .httpStatus(code, message):
            return "HTTP \(code)\(message.map { ": \($0)" } ?? "")"
        case let .decodingFailed(reason):
            return "Failed to decode InnerTube response: \(reason)"
        }
    }
}

public actor InnerTubeClient {
    public var locale: YouTubeLocale
    public var cookie: String?
    public var visitorData: String?
    public var dataSyncId: String?

    private var ownVisitorIds: [String: String] = [:]
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        locale: YouTubeLocale = YouTubeLocale(),
        cookie: String? = nil,
        visitorData: String? = nil,
        dataSyncId: String? = nil,
        session: URLSession? = nil
    ) {
        self.locale = locale
        self.cookie = cookie
        self.visitorData = visitorData
        self.dataSyncId = dataSyncId
        if let session {
            self.session = session
        } else {
            let cfg = URLSessionConfiguration.default
            cfg.timeoutIntervalForRequest = 8
            cfg.timeoutIntervalForResource = 16
            self.session = URLSession(configuration: cfg)
        }
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    /// Ensures a valid guest `visitorData` exists for web InnerTube & BotGuard PoToken minting.
    public func ensureGuestVisitorData() async -> String? {
        if let visitorData, !visitorData.isEmpty {
            return visitorData
        }
        if let minted = try? await mintVisitorId(for: .webRemix), !minted.isEmpty {
            self.visitorData = minted
            return minted
        }
        return nil
    }

    public func updateAuth(cookie: String?, visitorData: String?, dataSyncId: String?) {
        self.cookie = cookie
        self.visitorData = visitorData
        self.dataSyncId = dataSyncId
    }

    public func updateLocale(countryCode: String, languageCode: String) {
        let gl = countryCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let hl = languageCode.trimmingCharacters(in: .whitespacesAndNewlines)
        self.locale = YouTubeLocale(
            gl: gl.isEmpty ? "VN" : gl.uppercased(),
            hl: hl.isEmpty ? "vi" : hl.lowercased()
        )
    }

    public func resolvedVisitorId(for client: YouTubeClient) async -> String? {
        if !client.ownVisitorId {
            return visitorData
        }
        let key = "\(client.clientName):\(client.clientVersion)"
        if let existing = ownVisitorIds[key] {
            return existing
        }
        if let minted = try? await mintVisitorId(for: client) {
            ownVisitorIds[key] = minted
            return minted
        }
        return visitorData
    }

    public func invalidateOwnVisitorId(for client: YouTubeClient) {
        ownVisitorIds.removeValue(forKey: "\(client.clientName):\(client.clientVersion)")
    }

    public func mintVisitorId(for client: YouTubeClient) async throws -> String? {
        let context = client.toContext(locale: locale, visitorData: nil, dataSyncId: nil)
        let request = try buildRequest(
            endpoint: "visitor_id",
            client: client,
            body: VisitorIdBody(context: context),
            setLogin: false,
            visitorOverride: nil
        )
        let (data, _) = try await performWithRetry(request)
        let decoded = try decoder.decode(VisitorIdResponse.self, from: data)
        return decoded.responseContext?.visitorData
    }

    public func player(
        client: YouTubeClient,
        videoId: String,
        playlistId: String? = nil,
        signatureTimestamp: Int? = nil,
        poToken: String? = nil,
        setLogin: Bool = false
    ) async throws -> PlayerResponse {
        let visitor = await resolvedVisitorId(for: client)
        let effectiveDataSync = (setLogin && client.loginSupported) ? dataSyncId : nil
        let context = client.toContext(
            locale: locale,
            visitorData: visitor,
            dataSyncId: effectiveDataSync,
            embedVideoId: videoId
        )

        let playbackContext = signatureTimestamp.map {
            PlayerBody.PlaybackContext(
                contentPlaybackContext: .init(signatureTimestamp: $0)
            )
        }
        let integrity = poToken.map {
            PlayerBody.ServiceIntegrityDimensions(poToken: $0)
        }

        let body = PlayerBody(
            context: context,
            videoId: videoId,
            playlistId: playlistId,
            playbackContext: playbackContext,
            serviceIntegrityDimensions: integrity
        )

        let request = try buildRequest(
            endpoint: "player",
            client: client,
            body: body,
            setLogin: setLogin,
            visitorOverride: visitor
        )

        let (data, _) = try await performWithRetry(request)
        do {
            return try decoder.decode(PlayerResponse.self, from: data)
        } catch {
            throw InnerTubeError.decodingFailed(Self.describeDecodingError(error))
        }
    }

    private static func describeDecodingError(_ error: Error) -> String {
        guard let decodingError = error as? DecodingError else {
            return error.localizedDescription
        }
        func pathString(_ path: [CodingKey]) -> String {
            path.isEmpty ? "<root>" : path.map(\.stringValue).joined(separator: ".")
        }
        switch decodingError {
        case let .typeMismatch(type, ctx):
            return "typeMismatch(\(type)) at \(pathString(ctx.codingPath))"
        case let .valueNotFound(type, ctx):
            return "valueNotFound(\(type)) at \(pathString(ctx.codingPath))"
        case let .keyNotFound(key, ctx):
            let full = ctx.codingPath + [key]
            return "keyNotFound(\(key.stringValue)) at \(pathString(full))"
        case let .dataCorrupted(ctx):
            return "dataCorrupted at \(pathString(ctx.codingPath)): \(ctx.debugDescription)"
        @unknown default:
            return error.localizedDescription
        }
    }

    public func rawPost<Body: Encodable>(
        endpoint: String,
        client: YouTubeClient,
        body: Body,
        setLogin: Bool = false
    ) async throws -> Data {
        let visitor = await resolvedVisitorId(for: client)
        let request = try buildRequest(
            endpoint: endpoint,
            client: client,
            body: body,
            setLogin: setLogin,
            visitorOverride: visitor
        )
        let (data, _) = try await performWithRetry(request)
        return data
    }

    /// Builds a properly signed InnerTube `URLRequest` matching Mochy's `ytClient()` header contract.
    public func buildRequest<Body: Encodable>(
        endpoint: String,
        client: YouTubeClient,
        body: Body,
        setLogin: Bool,
        visitorOverride: String? = nil,
        timestamp: Int = Int(Date().timeIntervalSince1970)
    ) throws -> URLRequest {
        let trimmed = endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let urlString = "\(client.apiOrigin)/youtubei/v1/\(trimmed)?prettyPrint=false"
        guard let url = URL(string: urlString) else {
            throw InnerTubeError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let acceptLang = locale.hl == "en"
            ? "en-\(locale.gl),en;q=0.9"
            : "\(locale.hl)-\(locale.gl),\(locale.hl);q=0.9,en-US;q=0.7,en;q=0.6"
        request.setValue(acceptLang, forHTTPHeaderField: "Accept-Language")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue(client.apiFormatVersion, forHTTPHeaderField: "X-Goog-Api-Format-Version")
        request.setValue(client.clientId, forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue(client.clientVersion, forHTTPHeaderField: "X-YouTube-Client-Version")
        request.setValue(client.userAgent, forHTTPHeaderField: "User-Agent")

        if !client.isNativeApp {
            request.setValue(client.apiOrigin, forHTTPHeaderField: "X-Origin")
            request.setValue("\(client.apiOrigin)/", forHTTPHeaderField: "Referer")
        }

        let visitor = visitorOverride ?? visitorData
        if let visitor, !visitor.isEmpty {
            request.setValue(visitor, forHTTPHeaderField: "X-Goog-Visitor-Id")
        }

        if setLogin, client.loginSupported, let cookie, !cookie.isEmpty {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
            request.setValue("0", forHTTPHeaderField: "X-Goog-AuthUser")
            if let sapisid = CryptoUtils.extractSAPISID(from: cookie) {
                let auth = CryptoUtils.sapisidHash(
                    sapisid: sapisid,
                    origin: client.apiOrigin,
                    timestamp: timestamp
                )
                request.setValue(auth, forHTTPHeaderField: "Authorization")
            }
        }

        request.httpBody = try encoder.encode(body)
        return request
    }

    private func performWithRetry(_ request: URLRequest, maxAttempts: Int = 2) async throws -> (Data, HTTPURLResponse) {
        var lastError: Error?
        for attempt in 0..<maxAttempts {
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw InnerTubeError.httpStatus(-1, "Non-HTTP response")
                }
                if (200..<300).contains(http.statusCode) {
                    return (data, http)
                }
                // Never retry 4xx client errors.
                if (400..<500).contains(http.statusCode) {
                    throw InnerTubeError.httpStatus(http.statusCode, String(data: data.prefix(256), encoding: .utf8))
                }
                lastError = InnerTubeError.httpStatus(http.statusCode, nil)
            } catch let err as InnerTubeError {
                if case let .httpStatus(code, _) = err, (400..<500).contains(code) {
                    throw err
                }
                lastError = err
            } catch {
                lastError = error
            }

            if attempt + 1 < maxAttempts {
                let backoffNs = UInt64(250_000_000) * UInt64(1 << attempt)
                try? await Task.sleep(nanoseconds: backoffNs)
            }
        }
        throw lastError ?? InnerTubeError.httpStatus(-1, "Unknown failure")
    }
}
