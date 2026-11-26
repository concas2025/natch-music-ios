import Foundation
import JavaScriptCore

public enum EjsSolverError: Error, LocalizedError {
    case missingResource(String)
    case jsEvaluationFailed(String)
    case solverUnavailable(String)
    case invalidCipherParameters

    public var errorDescription: String? {
        switch self {
        case let .missingResource(name):
            return "Missing bundled EJS solver resource: \(name)"
        case let .jsEvaluationFailed(msg):
            return "EJS JavaScriptCore error: \(msg)"
        case let .solverUnavailable(kind):
            return "EJS \(kind) solver function was not discovered."
        case .invalidCipherParameters:
            return "Malformed signatureCipher parameters."
        }
    }
}

/// Native iOS `JavaScriptCore` runner executing Mochy's bundled EJS solver
/// (`meriyah.js`, `astring.js`, `yt.solver.core.js`) with zero WebView overhead.
public actor EjsSolver {
    private static let idleTimeoutNs: UInt64 = 60_000_000_000
    private static let nParamRegex = try! NSRegularExpression(pattern: #"([?&])n=([^&]+)"#)

    private let fetcher: PlayerJsFetcher
    private var context: JSContext?
    private var preparedHash: String?
    private var nSolverFn: JSValue?
    private var sigSolverFn: JSValue?
    private var idleTask: Task<Void, Never>?

    public init(fetcher: PlayerJsFetcher = PlayerJsFetcher()) {
        self.fetcher = fetcher
    }

    public func release() {
        idleTask?.cancel()
        idleTask = nil
        nSolverFn = nil
        sigSolverFn = nil
        context = nil
        preparedHash = nil
    }

    /// Verifies that the bundled EJS solver scripts parse cleanly in a `JSContext`.
    public static func createSolverContext() throws -> JSContext {
        guard let ctx = JSContext() else {
            throw EjsSolverError.jsEvaluationFailed("Could not allocate JSContext")
        }
        var lastJsError: String?
        ctx.exceptionHandler = { _, exception in
            lastJsError = exception?.toString()
        }

        for name in ["meriyah", "astring", "yt.solver.core"] {
            let script = try loadResourceScript(name: name)
            ctx.evaluateScript(script)
            if let err = lastJsError {
                throw EjsSolverError.jsEvaluationFailed("\(name).js: \(err)")
            }
        }
        return ctx
    }

    public func deobfuscateStreamURL(signatureCipher: String, forceRefresh: Bool = false) async throws -> String {
        let params = Self.parseQueryParams(signatureCipher)
        guard let obfuscatedSig = params["s"], let baseUrl = params["url"] else {
            throw EjsSolverError.invalidCipherParameters
        }
        let sigParam = params["sp"] ?? "signature"
        let solvedSig = try await solveSignature(obfuscatedSig, forceRefresh: forceRefresh)

        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "+&="))
        let encodedSig = solvedSig.addingPercentEncoding(withAllowedCharacters: allowed) ?? solvedSig
        let separator = baseUrl.contains("?") ? "&" : "?"
        let signedURL = "\(baseUrl)\(separator)\(sigParam)=\(encodedSig)"
        return try await transformNParam(in: signedURL)
    }

    public func transformNParam(in urlString: String) async throws -> String {
        let range = NSRange(urlString.startIndex..<urlString.endIndex, in: urlString)
        guard let match = Self.nParamRegex.firstMatch(in: urlString, range: range),
              match.numberOfRanges >= 3,
              let prefixRange = Range(match.range(at: 1), in: urlString),
              let valueRange = Range(match.range(at: 2), in: urlString) else {
            return urlString
        }

        let rawN = String(urlString[valueRange])
        let decodedN = rawN.removingPercentEncoding ?? rawN
        let solvedN = try await solveN(decodedN)

        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "+&="))
        let encodedN = solvedN.addingPercentEncoding(withAllowedCharacters: allowed) ?? solvedN
        let prefix = String(urlString[prefixRange])

        guard let fullMatchRange = Range(match.range(at: 0), in: urlString) else {
            return urlString
        }
        var updated = urlString
        updated.replaceSubrange(fullMatchRange, with: "\(prefix)n=\(encodedN)")
        return updated
    }

    public func solveSignature(_ sig: String, forceRefresh: Bool = false) async throws -> String {
        try await ensurePrepared(forceRefresh: forceRefresh)
        guard let fn = sigSolverFn, !fn.isUndefined, !fn.isNull else {
            throw EjsSolverError.solverUnavailable("sig")
        }
        guard let result = fn.call(withArguments: [sig])?.toString(), !result.isEmpty else {
            throw EjsSolverError.jsEvaluationFailed("sig solver returned empty value")
        }
        scheduleIdleRelease()
        return result
    }

    public func solveN(_ nValue: String, forceRefresh: Bool = false) async throws -> String {
        try await ensurePrepared(forceRefresh: forceRefresh)
        guard let fn = nSolverFn, !fn.isUndefined, !fn.isNull else {
            throw EjsSolverError.solverUnavailable("n")
        }
        guard let result = fn.call(withArguments: [nValue])?.toString(), !result.isEmpty else {
            throw EjsSolverError.jsEvaluationFailed("n solver returned empty value")
        }
        scheduleIdleRelease()
        return result
    }

    public func currentSignatureTimestamp() async throws -> Int? {
        let bundle = try await fetcher.getPlayerJs(forceRefresh: false)
        return bundle.signatureTimestamp
    }

    private func ensurePrepared(forceRefresh: Bool) async throws {
        let bundle = try await fetcher.getPlayerJs(forceRefresh: forceRefresh)
        if !forceRefresh, context != nil, preparedHash == bundle.hash,
           (nSolverFn != nil || sigSolverFn != nil) {
            return
        }

        let ctx = try Self.createSolverContext()
        var jsError: String?
        ctx.exceptionHandler = { _, exception in
            jsError = exception?.toString()
        }

        ctx.setObject(bundle.code, forKeyedSubscript: "__mochyPlayerJs" as NSString)
        let bootstrap = """
        (function() {
            var res = jsc({
                type: 'player',
                player: __mochyPlayerJs,
                requests: [],
                output_preprocessed: true
            });
            if (!res || res.type === 'error') {
                return { error: (res && res.error) ? String(res.error) : 'unknown preprocess error' };
            }
            var solvers = { n: null, sig: null };
            (new Function('_result', res.preprocessed_player))(solvers);
            __mochyN = solvers.n;
            __mochySig = solvers.sig;
            return {
                hasN: typeof solvers.n === 'function',
                hasSig: typeof solvers.sig === 'function'
            };
        })();
        """
        let status = ctx.evaluateScript(bootstrap)
        if let err = jsError {
            throw EjsSolverError.jsEvaluationFailed(err)
        }
        if let errorMsg = status?.objectForKeyedSubscript("error")?.toString(),
           errorMsg != "undefined", !errorMsg.isEmpty {
            throw EjsSolverError.jsEvaluationFailed(errorMsg)
        }

        self.context = ctx
        self.preparedHash = bundle.hash
        self.nSolverFn = ctx.objectForKeyedSubscript("__mochyN")
        self.sigSolverFn = ctx.objectForKeyedSubscript("__mochySig")
        scheduleIdleRelease()
    }

    private func scheduleIdleRelease() {
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.idleTimeoutNs)
            guard !Task.isCancelled else { return }
            await self?.release()
        }
    }

    private static func loadResourceScript(name: String) throws -> String {
        let url = Bundle.module.url(forResource: name, withExtension: "js", subdirectory: "solver")
            ?? Bundle.module.url(forResource: name, withExtension: "js")
        guard let url, let source = try? String(contentsOf: url, encoding: .utf8) else {
            throw EjsSolverError.missingResource("\(name).js")
        }
        return source
    }

    public static func parseQueryParams(_ query: String) -> [String: String] {
        var result: [String: String] = [:]
        for pair in query.split(separator: "&") {
            guard let eqIdx = pair.firstIndex(of: "=") else { continue }
            let rawKey = String(pair[..<eqIdx])
            let rawVal = String(pair[pair.index(after: eqIdx)...])
            let key = rawKey.removingPercentEncoding ?? rawKey
            let val = rawVal.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? rawVal
            result[key] = val
        }
        return result
    }
}
