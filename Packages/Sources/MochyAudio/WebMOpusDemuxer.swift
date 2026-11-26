import Foundation

public struct WebMOpusPacket: Sendable, Equatable {
    public let timestampMs: Int64
    public let data: Data
    public let isKeyframe: Bool

    public init(timestampMs: Int64, data: Data, isKeyframe: Bool = true) {
        self.timestampMs = timestampMs
        self.data = data
        self.isKeyframe = isKeyframe
    }
}

public struct WebMOpusTrack: Sendable, Equatable {
    public let trackNumber: UInt64
    public let sampleRate: Double
    public let channels: Int
    public let codecPrivate: Data
    public let packets: [WebMOpusPacket]
}

/// Lightweight EBML/Matroska audio demuxer extracting raw Opus packets from YouTube `audio/webm` streams.
public enum WebMOpusDemuxer {
    // EBML / Matroska element IDs
    private static let idEBML: UInt32 = 0x1A45DFA3
    private static let idSegment: UInt32 = 0x18538067
    private static let idTracks: UInt32 = 0x1654AE6B
    private static let idTrackEntry: UInt32 = 0xAE
    private static let idTrackNumber: UInt32 = 0xD7
    private static let idCodecID: UInt32 = 0x86
    private static let idCodecPrivate: UInt32 = 0x63A2
    private static let idAudio: UInt32 = 0xE1
    private static let idSamplingFrequency: UInt32 = 0xB5
    private static let idChannels: UInt32 = 0x9F
    private static let idCluster: UInt32 = 0x1F43B675
    private static let idTimecode: UInt32 = 0xE7
    private static let idBlockGroup: UInt32 = 0xA0
    private static let idBlock: UInt32 = 0xA1
    private static let idSimpleBlock: UInt32 = 0xA3

    public static func parse(data: Data) -> WebMOpusTrack? {
        var cursor = 0
        var targetTrackNumber: UInt64 = 1
        var isOpus = false
        var sampleRate: Double = 48_000
        var channels = 2
        var codecPrivate = Data()
        var packets: [WebMOpusPacket] = []

        func parseContainer(endOffset: Int, clusterTimecode: Int64 = 0) {
            var localClusterTime = clusterTimecode
            while cursor < endOffset {
                guard let (elemId, idLen) = readElementId(data, at: cursor) else { break }
                cursor += idLen
                guard let (sizeVal, sizeLen, isUnknown) = readVintSize(data, at: cursor) else { break }
                cursor += sizeLen

                let payloadEnd = isUnknown ? endOffset : min(endOffset, cursor + Int(sizeVal))
                switch elemId {
                case idSegment, idTracks, idTrackEntry, idAudio, idCluster, idBlockGroup:
                    parseContainer(endOffset: payloadEnd, clusterTimecode: localClusterTime)
                    if elemId == idCluster {
                        localClusterTime = 0
                    }
                case idEBML:
                    cursor = payloadEnd
                case idTrackNumber:
                    targetTrackNumber = readUInt(data, start: cursor, end: payloadEnd)
                    cursor = payloadEnd
                case idCodecID:
                    let str = String(data: data[cursor..<payloadEnd], encoding: .utf8) ?? ""
                    if str == "A_OPUS" { isOpus = true }
                    cursor = payloadEnd
                case idCodecPrivate:
                    codecPrivate = data[cursor..<payloadEnd]
                    cursor = payloadEnd
                case idSamplingFrequency:
                    if let rate = readFloat(data, start: cursor, end: payloadEnd), rate > 0 {
                        sampleRate = rate
                    }
                    cursor = payloadEnd
                case idChannels:
                    let ch = Int(readUInt(data, start: cursor, end: payloadEnd))
                    if ch > 0 { channels = ch }
                    cursor = payloadEnd
                case idTimecode:
                    localClusterTime = Int64(readUInt(data, start: cursor, end: payloadEnd))
                    cursor = payloadEnd
                case idSimpleBlock, idBlock:
                    let blockData = data[cursor..<payloadEnd]
                    let extracted = parseBlockFrames(
                        blockData,
                        clusterTimecode: localClusterTime,
                        expectedTrack: targetTrackNumber
                    )
                    packets.append(contentsOf: extracted)
                    cursor = payloadEnd
                default:
                    cursor = payloadEnd
                }
            }
        }

        parseContainer(endOffset: data.count)
        guard isOpus || !packets.isEmpty else { return nil }
        return WebMOpusTrack(
            trackNumber: targetTrackNumber,
            sampleRate: sampleRate,
            channels: channels,
            codecPrivate: codecPrivate,
            packets: packets
        )
    }

    private static func parseBlockFrames(
        _ slice: Data,
        clusterTimecode: Int64,
        expectedTrack: UInt64
    ) -> [WebMOpusPacket] {
        let bytes = [UInt8](slice)
        guard bytes.count >= 4 else { return [] }
        guard let (trackNum, trackLen, _) = readVintSize(Data(bytes), at: 0),
              trackNum == expectedTrack,
              trackLen + 3 <= bytes.count else {
            return []
        }

        let relHi = Int16(Int8(bitPattern: bytes[trackLen]))
        let relLo = Int16(bytes[trackLen + 1])
        let relativeTime = (relHi << 8) | relLo
        let flags = bytes[trackLen + 2]
        let keyframe = (flags & 0x80) != 0
        let lacing = (flags & 0x06) >> 1
        let payloadStart = trackLen + 3
        let timestampMs = clusterTimecode + Int64(relativeTime)

        if lacing == 0 {
            let packet = Data(bytes[payloadStart...])
            return packet.isEmpty ? [] : [WebMOpusPacket(timestampMs: timestampMs, data: packet, isKeyframe: keyframe)]
        }

        // Handle Xiph (1) / Fixed-size (2) / EBML (3) lacing
        guard payloadStart < bytes.count else { return [] }
        let frameCount = Int(bytes[payloadStart]) + 1
        var pos = payloadStart + 1
        var sizes: [Int] = []

        if lacing == 2 {
            let remaining = bytes.count - pos
            let each = remaining / max(1, frameCount)
            sizes = Array(repeating: each, count: frameCount)
        } else if lacing == 1 {
            for _ in 0..<(frameCount - 1) {
                var size = 0
                while pos < bytes.count {
                    let b = Int(bytes[pos])
                    pos += 1
                    size += b
                    if b != 255 { break }
                }
                sizes.append(size)
            }
            sizes.append(max(0, bytes.count - pos - sizes.reduce(0, +)))
        } else {
            // Single fallback if EBML lace sizes are malformed
            let rem = Data(bytes[pos...])
            return rem.isEmpty ? [] : [WebMOpusPacket(timestampMs: timestampMs, data: rem, isKeyframe: keyframe)]
        }

        var result: [WebMOpusPacket] = []
        for s in sizes where s > 0 && pos + s <= bytes.count {
            result.append(
                WebMOpusPacket(
                    timestampMs: timestampMs,
                    data: Data(bytes[pos..<(pos + s)]),
                    isKeyframe: keyframe
                )
            )
            pos += s
        }
        return result
    }

    private static func readElementId(_ data: Data, at offset: Int) -> (UInt32, Int)? {
        guard offset < data.count else { return nil }
        let first = data[offset]
        guard first != 0 else { return nil }
        let len = first.leadingZeroBitCount + 1
        guard len <= 4, offset + len <= data.count else { return nil }
        var val: UInt32 = 0
        for i in 0..<len {
            val = (val << 8) | UInt32(data[offset + i])
        }
        return (val, len)
    }

    private static func readVintSize(_ data: Data, at offset: Int) -> (UInt64, Int, Bool)? {
        guard offset < data.count else { return nil }
        let first = data[offset]
        guard first != 0 else { return nil }
        let len = first.leadingZeroBitCount + 1
        guard len <= 8, offset + len <= data.count else { return nil }
        let mask = UInt8(0xFF >> len)
        var val = UInt64(first & mask)
        for i in 1..<len {
            val = (val << 8) | UInt64(data[offset + i])
        }
        let allOnes = (UInt64(1) << (7 * len)) - 1
        return (val, len, val == allOnes)
    }

    private static func readUInt(_ data: Data, start: Int, end: Int) -> UInt64 {
        var val: UInt64 = 0
        for i in start..<min(end, data.count) {
            val = (val << 8) | UInt64(data[i])
        }
        return val
    }

    private static func readFloat(_ data: Data, start: Int, end: Int) -> Double? {
        let len = end - start
        if len == 4, end <= data.count {
            let raw = UInt32(readUInt(data, start: start, end: end))
            return Double(Float(bitPattern: raw))
        } else if len == 8, end <= data.count {
            let raw = readUInt(data, start: start, end: end)
            return Double(bitPattern: raw)
        }
        return nil
    }
}
