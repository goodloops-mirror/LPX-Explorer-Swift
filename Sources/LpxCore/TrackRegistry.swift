import Foundation

/// Track-registry records: one per user-visible track in the Tracks area (distinct
/// from channel strips, which include every bus/aux/instrument slot).
///
/// `<4 zeros> <2-byte signature> <4 bytes> <2 control> <2 zeros> <u16-LE length, hi byte 0> <ASCII name>`
public enum TrackRegistry {
    private static let nameMaxLen = 200
    private static let preambleLen = 16

    /// Empirically derived signatures. Buses and plug-in preset entries share the outer
    /// record shape, so the pairing step filters by strip-id range.
    private static let signatureKind: [UInt16: TrackKind] = {
        let table: [([UInt8], TrackKind)] = [
            ([0x22, 0x12], .instrument), ([0xa8, 0x11], .instrument), ([0xda, 0x11], .instrument), ([0xe7, 0x10], .instrument),
            ([0x03, 0x10], .instrument), ([0x4d, 0x10], .instrument), ([0x5f, 0x11], .instrument),
            ([0x23, 0x12], .audio), ([0xdc, 0x11], .audio), ([0xdf, 0x11], .audio), ([0x47, 0x11], .audio),
            ([0xc7, 0x10], .audio), ([0x4c, 0x10], .audio), ([0x9a, 0x11], .audio), ([0x7a, 0x11], .audio),
            ([0x74, 0x10], .folder), ([0xcb, 0x10], .folder), ([0xe3, 0x11], .folder), ([0xe4, 0x10], .folder),
            ([0xeb, 0x11], .folder), ([0xe7, 0x11], .folder), ([0x0d, 0x10], .folder), ([0x8d, 0x11], .folder),
        ]
        return Dictionary(uniqueKeysWithValues: table.map { (UInt16($0.0[0]) << 8 | UInt16($0.0[1]), $0.1) })
    }()

    /// Logic-internal placeholders / system buses. "Untitled" is deliberately NOT here.
    private static let noiseNames: Set<String> = [
        "@ (=Context Name)", "(Folder)", "Not Assigned", "Transform Parameter Set", "Unused",
        "Click", "MIDI Click", "Master", "Stereo Out", "Preview", "VCA 1",
    ]

    /// The track kind a whitelisted registry class stands for (nil for classes the parser doesn't recognise).
    public static func kind(forClass cls: UInt16) -> TrackKind? { signatureKind[cls.byteSwapped] }

    public static func findRecords(_ raw: [UInt8]) -> [TrackRegistryEntry] {
        raw.withUnsafeBufferPointer { findRecords(in: $0) }
    }

    public static func findRecords(in raw: UnsafeBufferPointer<UInt8>) -> [TrackRegistryEntry] {
        var out: [TrackRegistryEntry] = []
        let n = raw.count
        guard n >= preambleLen else { return out }
        // Candidate record start `i` has its signature's second byte (0x10...0x12) at i+5.
        // Jump between those bytes with three lazily-advanced memchr cursors.
        var cursor = [Int?](repeating: nil, count: 3), exhausted = [false, false, false]
        var scanFrom = 5 // earliest possible position of the signature's second byte
        var i = 0
        while true {
            var next = Int.max
            for k in 0..<3 where !exhausted[k] {
                if cursor[k] == nil || cursor[k]! < scanFrom {
                    if let p = ByteSearch.indexOf(UInt8(0x10 + k), in: raw, from: scanFrom) { cursor[k] = p } else { exhausted[k] = true; continue }
                }
                next = min(next, cursor[k]!)
            }
            guard next != Int.max else { break }
            i = next - 5
            scanFrom = next + 1
            guard i + preambleLen <= n else { break }
            if raw[i] | raw[i + 1] | raw[i + 2] | raw[i + 3] != 0 { i += 1; continue }
            guard let kind = signatureKind[UInt16(raw[i + 4]) << 8 | UInt16(raw[i + 5])] else { i += 1; continue }
            // bytes 6-9: all zero | ff ff 00 00 | XX 00 00 00 (category flag).
            let bytes69OK = (raw[i + 7] == 0 && raw[i + 8] == 0 && raw[i + 9] == 0)
                || (raw[i + 6] == 0xff && raw[i + 7] == 0xff && raw[i + 8] == 0 && raw[i + 9] == 0)
            guard bytes69OK, raw[i + 12] | raw[i + 13] == 0 else { i += 1; continue }
            let length = Int(raw[i + 14])
            guard raw[i + 15] == 0, length > 0, length <= nameMaxLen else { i += 1; continue }
            let nameOff = i + preambleLen
            guard nameOff + length <= n else { i += 1; continue }
            var printable = true
            for k in nameOff..<(nameOff + length) where raw[k] < 0x20 || raw[k] >= 0x7f { printable = false; break }
            guard printable else { i += 1; continue }
            let name = String(decoding: UnsafeBufferPointer(rebasing: raw[nameOff ..< nameOff + length]), as: UTF8.self)
            guard !noiseNames.contains(name) else { i += 1; continue }

            let trailerStart = nameOff + length
            let trailer = Array(UnsafeBufferPointer(rebasing: raw[trailerStart ..< min(n, trailerStart + 8)]))
            let entryKind: TrackKind = isSummingStackTrailer(trailer) ? .summingStack : kind
            let trackID: UInt16 = i >= 62 ? UInt16(raw[i - 62]) | UInt16(raw[i - 61]) << 8 : 0
            let stripID: UInt16 = (entryKind == .audio || entryKind == .instrument) ? decodeStripID(trailer) : 0
            out.append(TrackRegistryEntry(offset: i, name: name, kind: entryKind, trackID: trackID, stripID: stripID))
            scanFrom = trailerStart + 5 // skip past the name: next record's signature byte can't sit earlier
        }
        return out
    }

    /// Summing stacks carry `XX 01 00 NN 00 01` right after the name (optionally after one NUL).
    private static func isSummingStackTrailer(_ t: [UInt8]) -> Bool {
        for start in [0, 1] where t.count >= start + 6 {
            let c = t[start ..< start + 6].map { $0 }
            if c[1] == 0x01 && c[2] == 0x00 && c[4] == 0x00 && c[5] == 0x01 { return true }
        }
        return false
    }

    /// First non-zero u16-LE (< 512) after the name, at offset 0 or 1 (records are 2-byte aligned).
    private static func decodeStripID(_ t: [UInt8]) -> UInt16 {
        if t.count >= 2 { let v = UInt16(t[0]) | UInt16(t[1]) << 8; if v > 0 && v < 512 { return v } }
        if t.count >= 3 { let v = UInt16(t[1]) | UInt16(t[2]) << 8; if v > 0 && v < 512 { return v } }
        return 0
    }
}
