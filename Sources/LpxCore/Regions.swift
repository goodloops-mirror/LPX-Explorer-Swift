import Foundation

/// Region-record scanner. When a user renames "Audio 3" → "Acoustic GTR" the new
/// name lives in audio-region blocks, not in the channel-strip record:
/// `<4-byte id> 0x61 0xff <24 zeros> <uint16-LE length> <ascii name>`.
public enum Regions {
    private static let nameMaxLen = 200
    private static let marker: [UInt8] = [0x61, 0xff] + [UInt8](repeating: 0, count: 24)
    private static let markerLen = 26

    public static func findRecords(_ raw: [UInt8]) -> [RegionRecord] {
        raw.withUnsafeBufferPointer { findRecords(in: $0) }
    }

    public static func findRecords(in raw: UnsafeBufferPointer<UInt8>) -> [RegionRecord] {
        var out: [RegionRecord] = []
        let n = raw.count
        var i = 0
        // Jump between 0x61 bytes, then verify 0xff + 24 NULs.
        while i + markerLen + 2 <= n, let hit = ByteSearch.indexOf(0x61, in: raw, from: i), hit + markerLen + 2 <= n {
            i = hit
            guard raw[i + 1] == 0xff, isZero(raw, i + 2, markerLen - 2) else { i += 1; continue }
            let lenOff = i + markerLen
            let length = Int(raw[lenOff]) | Int(raw[lenOff + 1]) << 8
            let nameOff = lenOff + 2
            guard length > 0, length <= nameMaxLen, nameOff + length <= n else { i += 1; continue }
            var printable = true
            for k in nameOff..<(nameOff + length) where raw[k] < 0x20 || raw[k] >= 0x7f { printable = false; break }
            guard printable else { i += 1; continue }
            out.append(RegionRecord(offset: i, name: String(decoding: UnsafeBufferPointer(rebasing: raw[nameOff ..< nameOff + length]), as: UTF8.self)))
            i = nameOff + length // don't re-enter inside the name bytes
        }
        return out
    }

    @inline(__always)
    private static func isZero(_ raw: UnsafeBufferPointer<UInt8>, _ start: Int, _ count: Int) -> Bool {
        for k in start..<(start + count) where raw[k] != 0 { return false }
        return true
    }

    /// Group consecutive records by stripped base name; one run ≈ one user-perceived track.
    /// Bare comp tags and recording filenames neither open nor break clusters.
    public static func cluster(_ records: [RegionRecord]) -> [RegionCluster] {
        var out: [RegionCluster] = []
        for record in records {
            let cleaned = stripRegionSuffixes(record.name)
            guard isUserTrackName(cleaned) else { continue }
            if let last = out.last, last.baseName == cleaned {
                out[out.count - 1].count += 1
                out[out.count - 1].lastOffset = record.offset
            } else {
                out.append(RegionCluster(baseName: cleaned, firstOffset: record.offset, lastOffset: record.offset, count: 1))
            }
        }
        return out
    }

    /// `true` for Logic's default channel-strip names: `Audio 1`, `Inst 12`, `Output 1-2`, `Master`…
    public static func isAutoTrackName(_ name: String) -> Bool {
        let bytes = Array(name.utf8)
        var p = 0
        while p < bytes.count, isAlpha(bytes[p]) { p += 1 }
        guard ["Audio", "Inst", "Bus", "Aux", "Output", "Input", "Master"].contains(String(decoding: bytes[..<p], as: UTF8.self)) else { return false }
        let rest = Array(bytes[p...])
        if rest.isEmpty { return true }
        guard rest[0] == 0x20, rest.count > 1 else { return false }
        var i = 1
        let firstDigits = i
        while i < rest.count, isDigit(rest[i]) { i += 1 }
        guard i > firstDigits else { return false }
        if i == rest.count { return true }
        guard rest[i] == UInt8(ascii: "-") else { return false }
        i += 1
        let secondStart = i
        while i < rest.count, isDigit(rest[i]) { i += 1 }
        return i > secondStart && i == rest.count
    }

    // MARK: suffix stripping (all names are printable ASCII)

    static func stripRegionSuffixes(_ name: String) -> String {
        var current = trimEnd(Array(name.utf8))
        while true {
            let next = stripOnePass(current)
            if next == current { return String(decoding: current, as: UTF8.self) }
            current = next
        }
    }

    private static func stripOnePass(_ input: [UInt8]) -> [UInt8] {
        var s = input
        if let p = findComp(s) { s = Array(s[..<p]) }
        if let p = findTake(s, ": Take ") { s = Array(s[..<p]) }
        if let p = findTake(s, " - Take ") { s = Array(s[..<p]) }
        if let p = findTake(s, " #") { s = Array(s[..<p]) }
        if let p = findTrailingDotNumber(s) { s = Array(s[..<p]) }
        return trimEnd(s)
    }

    /// `": Comp A"`, `": Comp A.1"` — tail alphanumeric/dots, starting alphanumeric.
    private static func findComp(_ s: [UInt8]) -> Int? {
        let tag = Array(": Comp ".utf8)
        guard let pos = rfind(s, tag) else { return nil }
        let tail = s[(pos + tag.count)...]
        guard let first = tail.first, isAlnum(first), tail.allSatisfy({ isAlnum($0) || $0 == UInt8(ascii: ".") }) else { return nil }
        return pos
    }

    /// `": Take 14"`, `" - Take 14.1"`, `" #06"` — tail digits/dots.
    private static func findTake(_ s: [UInt8], _ tag: String) -> Int? {
        let t = Array(tag.utf8)
        guard let pos = rfind(s, t) else { return nil }
        let tail = s[(pos + t.count)...]
        guard !tail.isEmpty, tail.allSatisfy({ isDigit($0) || $0 == UInt8(ascii: ".") }) else { return nil }
        return pos
    }

    /// `".1"`, `".2"` — trailing numeric duplicate.
    private static func findTrailingDotNumber(_ s: [UInt8]) -> Int? {
        guard let pos = s.lastIndex(of: UInt8(ascii: ".")) else { return nil }
        let tail = s[(pos + 1)...]
        guard !tail.isEmpty, tail.allSatisfy(isDigit) else { return nil }
        return pos
    }

    private static func isUserTrackName(_ name: String) -> Bool {
        !name.isEmpty && !isBareCompTag(name) && !hasRecordingFilenameSuffix(name)
    }

    private static func isBareCompTag(_ name: String) -> Bool {
        let b = Array(name.utf8)
        return b.count == 6 && name.hasPrefix("Comp ") && b[5] >= 0x41 && b[5] <= 0x5a
    }

    /// `_<digits>` or `_<digits> #<digits>` at the end (recorded-file region names).
    private static func hasRecordingFilenameSuffix(_ name: String) -> Bool {
        let b = trimEnd(Array(name.utf8))
        guard let us = b.lastIndex(of: UInt8(ascii: "_")) else { return false }
        let tail = Array(b[(us + 1)...])
        var i = 0
        while i < tail.count, isDigit(tail[i]) { i += 1 }
        guard i > 0 else { return false }
        if i == tail.count { return true }
        while i < tail.count, tail[i] == 0x20 { i += 1 }
        guard i < tail.count, tail[i] == UInt8(ascii: "#") else { return false }
        i += 1
        let digitsStart = i
        while i < tail.count, isDigit(tail[i]) { i += 1 }
        return i > digitsStart && i == tail.count
    }

    // MARK: byte helpers

    private static func trimEnd(_ s: [UInt8]) -> [UInt8] {
        var end = s.count
        while end > 0, s[end - 1] == 0x20 { end -= 1 }
        return Array(s[..<end])
    }

    private static func rfind(_ hay: [UInt8], _ needle: [UInt8]) -> Int? {
        guard hay.count >= needle.count else { return nil }
        var i = hay.count - needle.count
        while i >= 0 {
            if hay[i] == needle[0], Array(hay[i ..< i + needle.count]) == needle { return i }
            i -= 1
        }
        return nil
    }

    private static func isDigit(_ b: UInt8) -> Bool { b >= 0x30 && b <= 0x39 }
    private static func isAlpha(_ b: UInt8) -> Bool { (b >= 0x41 && b <= 0x5a) || (b >= 0x61 && b <= 0x7a) }
    private static func isAlnum(_ b: UInt8) -> Bool { isDigit(b) || isAlpha(b) }
}
