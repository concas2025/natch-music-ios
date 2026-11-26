import Foundation

/// Prevents iOS `AVPlayer` from reporting doubled (2x) track durations on YouTube DASH fragmented MP4 (`fMP4`)
/// streams where both `moov` (`mvhd`/`tkhd`/`mdhd`) and `mvex`/`moof` fragments declare full track duration.
public enum MP4DurationNormalizer {
    private static let boxMoov: UInt32 = 0x6D6F6F76 // "moov"
    private static let boxMvex: UInt32 = 0x6D766578 // "mvex"
    private static let boxMvhd: UInt32 = 0x6D766864 // "mvhd"
    private static let boxTrak: UInt32 = 0x7472616B // "trak"
    private static let boxTkhd: UInt32 = 0x746B6864 // "tkhd"
    private static let boxMdia: UInt32 = 0x6D646961 // "mdia"
    private static let boxMdhd: UInt32 = 0x6D646864 // "mdhd"

    /// Zeroes `mvhd`, `tkhd`, and `mdhd` duration fields in-place (preserving exact byte length)
    /// when a top-level `moov` box contains an `mvex` child box.
    public static func normalizeFragmentedMp4Header(_ input: Data) -> (data: Data, patched: Bool) {
        guard input.count >= 16 else { return (input, false) }
        var bytes = [UInt8](input)
        var offset = 0
        var patched = false

        while offset + 8 <= bytes.count {
            guard let (boxStart, payloadStart, boxEnd, boxType) = readBox(bytes, at: offset, limit: bytes.count) else {
                break
            }
            if boxType == boxMoov {
                if containerHasChild(bytes, start: payloadStart, end: boxEnd, targetType: boxMvex) {
                    if zeroDurationsInMoov(&bytes, start: payloadStart, end: boxEnd) {
                        patched = true
                    }
                }
                break
            }
            if boxEnd <= boxStart { break }
            offset = boxEnd
        }

        return patched ? (Data(bytes), true) : (input, false)
    }

    /// Authoritative duration sanity guard comparing `AVPlayerItem.duration` against catalog metadata duration.
    public static func resolveEffectiveDuration(reported: TimeInterval, known: TimeInterval?) -> TimeInterval {
        let validReported = (reported.isFinite && reported > 0) ? reported : 0
        guard let known, known.isFinite, known > 0 else {
            return validReported
        }
        guard validReported > 0 else {
            return known
        }
        // Reject CoreMedia 2x phantom duration or truncated mis-estimates outside [0.65x - 5s, 1.35x + 5s].
        if validReported > known * 1.35 + 5.0 || validReported < known * 0.65 - 5.0 {
            return known
        }
        return validReported
    }

    private static func readBox(_ bytes: [UInt8], at offset: Int, limit: Int) -> (start: Int, payloadStart: Int, end: Int, type: UInt32)? {
        guard offset + 8 <= limit else { return nil }
        let rawSize = readUInt32(bytes, at: offset)
        let boxType = readUInt32(bytes, at: offset + 4)

        let payloadStart: Int
        let boxEnd: Int
        if rawSize == 0 {
            payloadStart = offset + 8
            boxEnd = limit
        } else if rawSize == 1 {
            guard offset + 16 <= limit else { return nil }
            let extSize = readUInt64(bytes, at: offset + 8)
            guard extSize >= 16, extSize <= UInt64(limit - offset) else { return nil }
            payloadStart = offset + 16
            boxEnd = offset + Int(extSize)
        } else {
            let sizeInt = Int(rawSize)
            guard sizeInt >= 8, offset + sizeInt <= limit else { return nil }
            payloadStart = offset + 8
            boxEnd = offset + sizeInt
        }
        return (offset, payloadStart, boxEnd, boxType)
    }

    private static func containerHasChild(_ bytes: [UInt8], start: Int, end: Int, targetType: UInt32) -> Bool {
        var cursor = start
        while cursor + 8 <= end {
            guard let (s, _, next, type) = readBox(bytes, at: cursor, limit: end) else { return false }
            if type == targetType { return true }
            if next <= s { return false }
            cursor = next
        }
        return false
    }

    private static func zeroDurationsInMoov(_ bytes: inout [UInt8], start: Int, end: Int) -> Bool {
        var changed = false
        var cursor = start
        while cursor + 8 <= end {
            guard let (s, payload, next, type) = readBox(bytes, at: cursor, limit: end) else { break }
            switch type {
            case boxMvhd:
                if zeroFullBoxDuration(&bytes, payloadStart: payload, boxEnd: next, v0Offset: 16, v1Offset: 24) {
                    changed = true
                }
            case boxTrak:
                if zeroDurationsInTrak(&bytes, start: payload, end: next) {
                    changed = true
                }
            default:
                break
            }
            if next <= s { break }
            cursor = next
        }
        return changed
    }

    private static func zeroDurationsInTrak(_ bytes: inout [UInt8], start: Int, end: Int) -> Bool {
        var changed = false
        var cursor = start
        while cursor + 8 <= end {
            guard let (s, payload, next, type) = readBox(bytes, at: cursor, limit: end) else { break }
            switch type {
            case boxTkhd:
                if zeroFullBoxDuration(&bytes, payloadStart: payload, boxEnd: next, v0Offset: 20, v1Offset: 28) {
                    changed = true
                }
            case boxMdia:
                if zeroDurationsInMdia(&bytes, start: payload, end: next) {
                    changed = true
                }
            default:
                break
            }
            if next <= s { break }
            cursor = next
        }
        return changed
    }

    private static func zeroDurationsInMdia(_ bytes: inout [UInt8], start: Int, end: Int) -> Bool {
        var changed = false
        var cursor = start
        while cursor + 8 <= end {
            guard let (s, payload, next, type) = readBox(bytes, at: cursor, limit: end) else { break }
            if type == boxMdhd {
                if zeroFullBoxDuration(&bytes, payloadStart: payload, boxEnd: next, v0Offset: 16, v1Offset: 24) {
                    changed = true
                }
            }
            if next <= s { break }
            cursor = next
        }
        return changed
    }

    private static func zeroFullBoxDuration(
        _ bytes: inout [UInt8],
        payloadStart: Int,
        boxEnd: Int,
        v0Offset: Int,
        v1Offset: Int
    ) -> Bool {
        guard payloadStart + 4 <= boxEnd else { return false }
        let version = bytes[payloadStart]
        let fieldOffset: Int
        let fieldLen: Int
        if version == 0 {
            fieldOffset = payloadStart + v0Offset
            fieldLen = 4
        } else if version == 1 {
            fieldOffset = payloadStart + v1Offset
            fieldLen = 8
        } else {
            return false
        }
        guard fieldOffset + fieldLen <= boxEnd else { return false }
        var hadNonZero = false
        for i in fieldOffset..<(fieldOffset + fieldLen) {
            if bytes[i] != 0 {
                bytes[i] = 0
                hadNonZero = true
            }
        }
        return hadNonZero
    }

    private static func readUInt32(_ bytes: [UInt8], at idx: Int) -> UInt32 {
        (UInt32(bytes[idx]) << 24)
            | (UInt32(bytes[idx + 1]) << 16)
            | (UInt32(bytes[idx + 2]) << 8)
            | UInt32(bytes[idx + 3])
    }

    private static func readUInt64(_ bytes: [UInt8], at idx: Int) -> UInt64 {
        (UInt64(readUInt32(bytes, at: idx)) << 32) | UInt64(readUInt32(bytes, at: idx + 4))
    }
}
