import Foundation

public enum ThumbnailURLUpgrader {
    private static let googleWHRegex = try! NSRegularExpression(pattern: #"=w\d+-h\d+[^&\s]*"#)
    private static let googleSRegex = try! NSRegularExpression(pattern: #"=s\d+[^&\s]*"#)

    public static func upgrade(_ urlString: String?, size: Int = 720) -> String? {
        guard let raw = urlString?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return urlString
        }
        let lower = raw.lowercased()
        if lower.hasPrefix("file://") {
            return raw
        }

        let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        if lower.contains("googleusercontent.com") || lower.contains("ggpht.com") {
            if googleWHRegex.firstMatch(in: raw, range: range) != nil {
                return googleWHRegex.stringByReplacingMatches(
                    in: raw,
                    range: range,
                    withTemplate: "=w\(size)-h\(size)-l90-rj"
                )
            }
            if googleSRegex.firstMatch(in: raw, range: range) != nil {
                return googleSRegex.stringByReplacingMatches(
                    in: raw,
                    range: range,
                    withTemplate: "=s\(size)-c-k-c0x00ffffff-no-rj"
                )
            }
        }

        if lower.contains("ytimg.com") {
            if raw.contains("/default.jpg") {
                return raw.replacingOccurrences(of: "/default.jpg", with: "/hqdefault.jpg")
            }
            if raw.contains("/mqdefault.jpg") {
                return raw.replacingOccurrences(of: "/mqdefault.jpg", with: "/hqdefault.jpg")
            }
        }

        return raw
    }
}
