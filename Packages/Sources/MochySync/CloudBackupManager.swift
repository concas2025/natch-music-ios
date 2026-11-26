import Foundation
import MochyDatabase

/// Manages local Transfer Archive backups, iCloud Drive ubiquity sync, and WebDAV uploads.
public actor CloudBackupManager {
    public static let backgroundTaskIdentifier = "com.mochyy.mochymusic.backup"
    private let database: MochyDatabase
    private let session: URLSession

    public init(database: MochyDatabase, session: URLSession = .shared) {
        self.database = database
        self.session = session
    }

    public func saveToICloudDrive(filename: String = "mochy_backup.json") throws -> URL? {
        guard let container = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
            return nil
        }
        let docs = container.appendingPathComponent("Documents", isDirectory: true)
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        let target = docs.appendingPathComponent(filename)
        let payload = try TransferArchive.exportJSON(from: database)
        try payload.write(to: target, options: .atomic)
        return target
    }

    public func uploadWebDAV(endpoint: URL, username: String, password: String) async throws -> Bool {
        let payload = try TransferArchive.exportJSON(from: database)
        var req = URLRequest(url: endpoint.appendingPathComponent("mochy_backup.json"))
        req.httpMethod = "PUT"
        req.httpBody = payload
        let creds = Data("\(username):\(password)".utf8).base64EncodedString()
        req.setValue("Basic \(creds)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (_, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { return false }
        return (200..<300).contains(http.statusCode)
    }
}
