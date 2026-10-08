import Foundation

/// One entry of Logic's arrangement track list: a `karT` record (object id 4) of 93 bytes (92 in files written by Logic
/// Pro X 10.5 and earlier — the same fields, one byte less of tail). Records are stored back to back in track order,
/// hidden tracks included.
public struct ArrangementRecord: Equatable, Sendable {
    /// 1-based track number as Logic shows it.
    public var position: Int
    /// `qSxT` text object holding this track's own name; 0 = the track shows its object's name.
    public var nameTextID: UInt32
    /// Key of the object (channel strip) the track belongs to. Folder tracks all share key 0x10.
    public var objectKey: UInt32
    public var isHidden: Bool
    /// Byte offset of the record (the `karT` tag).
    public var offset: Int
}

public enum ArrangementList {
    /// Record sizes seen so far: Logic Pro 11 writes 93 bytes (record version 5), Logic Pro X 10.5 wrote 92 (version 4).
    private static let strides = [93, 92]
    private static let outputType: UInt8 = 3          // the "Stereo Out" record that ends the list
    private static let hiddenBit: UInt8 = 0x04

    /// The track records of the project, in track order. Empty when the file has no recognisable list.
    ///
    /// The list is the longest run of `karT` (id 4) records spaced exactly one record size apart (see `strides`) whose
    /// index counter (u32 at +22) starts at 0 and increases by one per record. The output record (type byte 3) and the
    /// trailing sentinel (index 0x7fffffff, which breaks the counter) are not tracks.
    public static func records(in raw: UnsafeBufferPointer<UInt8>) -> [ArrangementRecord] {
        let n = raw.count
        var tags: [Int] = []
        var from = 4
        while let k = ByteSearch.indexOf(UInt8(ascii: "k"), in: raw, from: from) {
            from = k + 1
            guard k >= 4, k + (strides.min() ?? 93) - 4 <= n, isHeader(raw, tag: k) else { continue }
            tags.append(k)
        }
        var best: [Int] = []
        for stride in strides {
            var i = 0
            while i < tags.count {
                // start of a candidate run: index counter 0
                guard u32(raw, tags[i] - 4 + 22) == 0, tags[i] - 4 + stride <= n else { i += 1; continue }
                var run = [tags[i]]
                var j = i + 1
                while j < tags.count, tags[j] - tags[j - 1] == stride, u32(raw, tags[j] - 4 + 22) == UInt32(run.count) {
                    run.append(tags[j]); j += 1
                }
                if run.count > best.count { best = run }
                i = max(j, i + 1)
            }
        }
        return best.compactMap { t -> ArrangementRecord? in
            let r = t - 4
            guard raw[r + 40] != outputType else { return nil }
            return ArrangementRecord(
                position: Int(u32(raw, r + 22)) + 1, nameTextID: u32(raw, r + 44), objectKey: u32(raw, r + 48),
                isHidden: raw[r + 43] & hiddenBit != 0, offset: t)
        }
    }

    public static func records(_ raw: [UInt8]) -> [ArrangementRecord] { raw.withUnsafeBufferPointer { records(in: $0) } }

    /// `karT` · version · 0x17|0x20 · … · object id 4.
    private static func isHeader(_ raw: UnsafeBufferPointer<UInt8>, tag t: Int) -> Bool {
        raw[t + 1] == 0x61 && raw[t + 2] == 0x72 && raw[t + 3] == 0x54                    // "arT"
            && raw[t + 5] == 0 && (raw[t + 6] == 0x17 || raw[t + 6] == 0x20) && raw[t + 7] == 0
            && raw[t + 10] == 4 && raw[t + 11] == 0 && raw[t + 12] == 0 && raw[t + 13] == 0
    }

    private static func u32(_ raw: UnsafeBufferPointer<UInt8>, _ p: Int) -> UInt32 {
        UInt32(raw[p]) | UInt32(raw[p + 1]) << 8 | UInt32(raw[p + 2]) << 16 | UInt32(raw[p + 3]) << 24
    }
}

/// `qSxT` text objects: track/object names (and RTF notes, which are ignored).
public enum NameTexts {
    /// text-object id → text. Layout: tag `qSxT`, id at +10, size at +28 (text length = size − 99), text at +134.
    /// RTF notes and non-text payloads are skipped; names are UTF-8 with trailing NULs removed.
    public static func find(in raw: UnsafeBufferPointer<UInt8>) -> [UInt32: String] {
        var out: [UInt32: String] = [:]
        let n = raw.count
        var from = 0
        while let q = ByteSearch.indexOf(UInt8(ascii: "q"), in: raw, from: from) {
            from = q + 1
            guard q + 134 <= n, raw[q + 1] == 0x53, raw[q + 2] == 0x78, raw[q + 3] == 0x54,       // "SxT"
                  raw[q + 4] == 0x01, raw[q + 5] == 0, raw[q + 6] == 0x20, raw[q + 7] == 0 else { continue }
            let id = u32(raw, q + 10)
            let textLength = Int(u32(raw, q + 28)) - 99
            guard textLength > 0, textLength <= 2000, q + 134 + textLength <= n, out[id] == nil else { continue }
            var end = q + 134 + textLength
            while end > q + 134, raw[end - 1] == 0 { end -= 1 }
            guard end > q + 134 else { continue }
            let bytes = UnsafeBufferPointer(rebasing: raw[(q + 134) ..< end])
            guard bytes.allSatisfy({ $0 >= 0x20 }) else { continue }                                  // control chars ⇒ not a name
            let text = String(decoding: bytes, as: UTF8.self)
            if text.hasPrefix("//") || text.hasPrefix("{\\rtf") || text.contains("\u{FFFD}") { continue }
            out[id] = text
        }
        return out
    }

    public static func find(_ raw: [UInt8]) -> [UInt32: String] { raw.withUnsafeBufferPointer { find(in: $0) } }

    private static func u32(_ raw: UnsafeBufferPointer<UInt8>, _ p: Int) -> UInt32 {
        UInt32(raw[p]) | UInt32(raw[p + 1]) << 8 | UInt32(raw[p + 2]) << 16 | UInt32(raw[p + 3]) << 24
    }
}

/// A registry-shaped name record of ANY object class (the registry parser only whitelists some classes).
public struct ObjectRecord: Equatable, Sendable {
    public var offset: Int
    public var name: String
    public var classNumber: UInt16
    public var key: UInt32
    /// Strip number from the record trailer. The trailer's alignment varies, so a second candidate is kept
    /// (0 when there is none); the strip lookup tries both.
    public var stripID: UInt16
    public var altStripID: UInt16 = 0
}

public enum TrackObjects {
    /// Object records that carry a valid key (the same non-zero u32 stored 170 and 128 bytes before the record).
    /// Layout: `4 zeros · class u16 · bytes 6-9 (x000) · 2 control bytes · 2 zeros · length · printable name · trailer`.
    ///
    /// `lenient` accepts records whose first two bytes are not zero (files written by Logic Pro X 10.5 and earlier pack the
    /// record right behind the previous text); it is only meant as a fallback, see `complete`.
    public static func find(in raw: UnsafeBufferPointer<UInt8>, lenient: Bool = false) -> [ObjectRecord] {
        var out: [ObjectRecord] = []
        let n = raw.count
        guard n >= 186 else { return out }
        // Candidate starts: the class's high byte (0x10…0x12) sits at i+5. Jump with three memchr cursors.
        var cursor = [Int?](repeating: nil, count: 3), exhausted = [false, false, false]
        var scanFrom = 170 + 5
        while true {
            var next = Int.max
            for k in 0..<3 where !exhausted[k] {
                if cursor[k] == nil || cursor[k]! < scanFrom {
                    if let p = ByteSearch.indexOf(UInt8(0x10 + k), in: raw, from: scanFrom) { cursor[k] = p } else { exhausted[k] = true; continue }
                }
                next = min(next, cursor[k]!)
            }
            guard next != Int.max else { break }
            let i = next - 5
            scanFrom = next + 1
            guard i + 16 <= n else { break }
            guard (lenient ? raw[i + 2] | raw[i + 3] : raw[i] | raw[i + 1] | raw[i + 2] | raw[i + 3]) == 0,
                  raw[i + 7] == 0, raw[i + 8] == 0, raw[i + 9] == 0, raw[i + 12] | raw[i + 13] == 0, raw[i + 15] == 0 else { continue }
            let length = Int(raw[i + 14])
            guard length > 0, length <= 200, i + 16 + length <= n else { continue }
            let nameBytes = UnsafeBufferPointer(rebasing: raw[(i + 16) ..< (i + 16 + length)])
            guard nameBytes.allSatisfy({ $0 >= 0x20 && $0 < 0x7f }) else { continue }
            let a = u32(raw, i - 170), b = u32(raw, i - 128)
            guard a == b, a != 0 else { continue }
            let trailerStart = i + 16 + length
            let trailer = Array(UnsafeBufferPointer(rebasing: raw[trailerStart ..< min(n, trailerStart + 8)]))
            let ids = stripIDs(trailer)
            out.append(ObjectRecord(offset: i, name: String(decoding: nameBytes, as: UTF8.self),
                                    classNumber: UInt16(raw[i + 4]) | UInt16(raw[i + 5]) << 8, key: a,
                                    stripID: ids.primary, altStripID: ids.alternative))
            scanFrom = max(scanFrom, trailerStart + 5) // skip past the name, like the registry scan
        }
        return out
    }

    public static func find(_ raw: [UInt8], lenient: Bool = false) -> [ObjectRecord] { raw.withUnsafeBufferPointer { find(in: $0, lenient: lenient) } }

    /// `strict` plus — only for object keys in `needed` that strict found nowhere — the lenient matches. Files whose objects
    /// are all found strictly never run the lenient pass, and a lenient match can never shadow a strict one.
    public static func complete(_ strict: [ObjectRecord], needing needed: Set<UInt32>, in raw: UnsafeBufferPointer<UInt8>) -> [ObjectRecord] {
        let have = Set(strict.map(\.key))
        guard !needed.subtracting(have).isEmpty else { return strict }
        let missing = needed.subtracting(have)
        return strict + find(in: raw, lenient: true).filter { missing.contains($0.key) }
    }

    /// The strip number sits at offset 0 or 1 of the trailer (the alignment varies), as a u16 below 512. Both readings are
    /// returned when both look plausible; the first is what the registry parser would pick.
    private static func stripIDs(_ t: [UInt8]) -> (primary: UInt16, alternative: UInt16) {
        func value(at k: Int) -> UInt16? {
            guard t.count >= k + 2 else { return nil }
            let v = UInt16(t[k]) | UInt16(t[k + 1]) << 8
            return v > 0 && v < 512 ? v : nil
        }
        let a = value(at: 0), b = value(at: 1)
        return (a ?? b ?? 0, (a != nil && b != nil && a != b) ? b! : 0)
    }

    private static func u32(_ raw: UnsafeBufferPointer<UInt8>, _ p: Int) -> UInt32 {
        UInt32(raw[p]) | UInt32(raw[p + 1]) << 8 | UInt32(raw[p + 2]) << 16 | UInt32(raw[p + 3]) << 24
    }
}
