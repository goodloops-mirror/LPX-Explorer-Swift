import Foundation

/// Apple stock plug-ins (Compressor, Alchemy, ChromaVerb…) are not stored as 4CC
/// triples; they sit in slot records anchored on the `GAME` marker, laid out
/// relative to the `G`:
///
///     -14 flag1 | -13 flag2 | -12 … -1 name (12 bytes, NUL padded) | GAME
///
/// flag2 is 0x02 for regular slots (0x01 for Klopfgeist, the metronome); flag1 is
/// 0x02 for effect inserts and 0x00 for instrument slots. The real 4CC triple is
/// not recoverable, so a plausible one is synthesised unless the name is in the
/// verified table.
public enum AppleStock {
    private static let nameFieldLen = 12
    private static let marker: [UInt8] = Array("GAME".utf8)
    private static let fxFlag2: UInt8 = 0x02
    private static let klopfgeistFlag2: UInt8 = 0x01

    /// Names verified against `auval -l` from a stock Logic install. Guessing a
    /// subtype risks false positives in compatibility checks, so only add verified ones.
    private static let stockFingerprints: [String: (type: String, subtype: String)] = [
        "Compressor": ("aufx", "Comp"),
    ]

    public static func findAUs(_ raw: [UInt8]) -> [AURef] { raw.withUnsafeBufferPointer { findAUs(in: $0) } }

    public static func findAUs(in raw: UnsafeBufferPointer<UInt8>) -> [AURef] {
        var out: [AURef] = []
        let n = raw.count
        guard n >= nameFieldLen + marker.count + 2 else { return out }
        var i = nameFieldLen + 2 // earliest position GAME could sit
        while let hit = ByteSearch.indexOf(marker[0], in: raw, from: i), hit + 4 <= n {
            i = hit
            guard raw[i + 1] == marker[1], raw[i + 2] == marker[2], raw[i + 3] == marker[3] else { i += 1; continue }
            let nameStart = i - nameFieldLen
            let flag1 = raw[nameStart - 2], flag2 = raw[nameStart - 1]
            guard flag2 == fxFlag2 || flag2 == klopfgeistFlag2 else { i += 1; continue }
            let kindType: String
            switch flag1 {
            case 0x02: kindType = "aufx"
            case 0x00: kindType = "aumu"
            default: i += 1; continue
            }
            var nameEnd = nameFieldLen
            for k in 0..<nameFieldLen where raw[nameStart + k] == 0 { nameEnd = k; break }
            guard nameEnd > 0 else { i += 1; continue }
            var valid = true
            for k in 0..<nameEnd where raw[nameStart + k] < 0x20 || raw[nameStart + k] > 0x7e { valid = false; break }
            // Everything after the name inside the field must be NUL, else it's ASCII garbage before a stray GAME.
            if valid { for k in nameEnd..<nameFieldLen where raw[nameStart + k] != 0 { valid = false; break } }
            guard valid else { i += 1; continue }
            let name = String(decoding: UnsafeBufferPointer(rebasing: raw[nameStart ..< nameStart + nameEnd]), as: UTF8.self)
            let (type, subtype) = lookupStockFingerprint(name) ?? (kindType, synthSubtype(name))
            out.append(AURef(typeCode: type, subtype: subtype, manufacturer: "appl", offset: nameStart, displayName: name))
            i += marker.count // don't match the same record twice
        }
        return out
    }

    static func lookupStockFingerprint(_ name: String) -> (type: String, subtype: String)? { stockFingerprints[name] }

    /// Deterministic 4-char lowercase subtype: alphanumerics only, padded with 'x'.
    static func synthSubtype(_ name: String) -> String {
        var s = name.unicodeScalars.filter { $0.isASCII && (("a"..."z").contains($0) || ("A"..."Z").contains($0) || ("0"..."9").contains($0)) }
            .map { Character($0).lowercased() }.joined()
        s = String(s.prefix(4))
        return s + String(repeating: "x", count: 4 - s.count)
    }
}
