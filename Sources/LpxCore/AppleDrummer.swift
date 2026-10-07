import Foundation

/// Apple Drummer / Bass Player is not stored as a 4CC triple or a `GAME` slot; its
/// identity lives in embedded JSON state (`"selectedPersistentCharacterTypeIdentifier":"Type_…"`).
/// One plug-in slot yields many nearby per-region snapshots, so hits are clustered
/// by byte-offset proximity and one AURef is emitted per cluster, using the latest
/// character type in the cluster as the active state.
public enum AppleDrummer {
    static let clusterThreshold = 32_768
    static let maxTypeValueLen = 96
    private static let needle: [UInt8] = Array(#""selectedPersistentCharacterTypeIdentifier":""#.utf8)
    private static let typePrefix = "Type_"

    public static func findAUs(_ raw: [UInt8]) -> [AURef] { raw.withUnsafeBufferPointer { findAUs(in: $0) } }

    public static func findAUs(in raw: UnsafeBufferPointer<UInt8>) -> [AURef] {
        var hits: [(offset: Int, value: String)] = []
        let n = raw.count, k = needle.count
        var i = 0
        // Anchor on the capital 'P' of "Persistent" (index 9; rare in binary), then verify the rest.
        let anchor = 9
        while i + k < n, let p = ByteSearch.indexOf(needle[anchor], in: raw, from: i + anchor) {
            i = p - anchor
            guard i + k < n, matches(raw, at: i) else { i += 1; continue }
            let valueStart = i + k
            let scanEnd = min(valueStart + maxTypeValueLen, n)
            var close = -1
            for j in valueStart..<scanEnd where raw[j] == UInt8(ascii: "\"") { close = j; break }
            guard close >= 0 else { i += 1; continue }
            if let s = String(validatingUTF8Bytes: raw, valueStart, close), s.hasPrefix(typePrefix), s.count > typePrefix.count {
                hits.append((i, s))
            }
            i = close + 1
        }
        guard let firstHit = hits.first else { return [] }

        var out: [AURef] = []
        var clusterStart = firstHit.offset, last = firstHit.offset, latest = firstHit.value
        for hit in hits.dropFirst() {
            if hit.offset - last > clusterThreshold {
                out.append(auRef(clusterStart, latest))
                clusterStart = hit.offset
            }
            last = hit.offset
            latest = hit.value
        }
        out.append(auRef(clusterStart, latest))
        return out
    }

    private static func matches(_ raw: UnsafeBufferPointer<UInt8>, at i: Int) -> Bool {
        for j in 0..<needle.count where raw[i + j] != needle[j] { return false }
        return true
    }

    private static func auRef(_ offset: Int, _ typeID: String) -> AURef {
        let name = displayName(forType: typeID)
        return AURef(typeCode: "aumu", subtype: AppleStock.synthSubtype(name), manufacturer: "appl", offset: offset, displayName: name)
    }

    private static func displayName(forType id: String) -> String {
        switch id {
        case "Type_AcousticDrummerV2": return "Drummer"
        case "Type_ElectricBassV2": return "Bass Player"
        default: return id.hasPrefix(typePrefix) ? String(id.dropFirst(typePrefix.count)) : id
        }
    }
}

private extension String {
    /// Strict UTF-8 decode of `raw[start..<end]`; nil when the bytes aren't valid UTF-8.
    init?(validatingUTF8Bytes raw: UnsafeBufferPointer<UInt8>, _ start: Int, _ end: Int) {
        var bytes = Array(UnsafeBufferPointer(rebasing: raw[start ..< end])).map { CChar(bitPattern: $0) }
        bytes.append(0)
        guard !bytes.dropLast().contains(0), let s = String(validatingUTF8: bytes) else { return nil }
        self = s
    }
}
